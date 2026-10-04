"""Reproducible, isolated four-turn rest-basis retarget. Never invokes Godot.

Reads the user ZIP and original GLB. Output is experiment-only and does not replace
the source animation library. Source keys are baked at their exact 30-Hz times.
"""
from __future__ import annotations
import argparse, hashlib, json, math, struct, zipfile, zlib
from pathlib import Path, PurePosixPath
import numpy as np
from mixamo_contact_correct import correct

WORKSPACE = Path(__file__).resolve().parent.parent
ARCHIVE = Path(r"E:\backup\Locomotion Pack.zip")
ARCHIVE_SHA = "e838c2f95645d2202b88ae972adb9560aefae0bfcb13e2082a4e37b4b70aac86"
TICKS = 46186158000
FILES = ["left turn.fbx", "right turn.fbx", "left turn 90.fbx", "right turn 90.fbx"]
MAP = {"hips":"Hips", "thighL":"LeftUpLeg", "shinL":"LeftLeg", "footL":"LeftFoot", "toeL":"LeftToeBase", "thighR":"RightUpLeg", "shinR":"RightLeg", "footR":"RightFoot", "toeR":"RightToeBase"}

class Node:
    def __init__(self, name, props, children): self.name,self.props,self.children=name,props,children
    def child(self,name): return next((n for n in self.children if n.name==name),None)
    def value(self,name,default=None):
        n=self.child(name); return n.props[0] if n and n.props else default

def parse_fbx(data):
    if not data.startswith(b"Kaydara FBX Binary  \x00\x1a\x00"): raise ValueError("Not binary FBX")
    version=struct.unpack_from("<I",data,23)[0]
    fmt,size=("<QQQB",25) if version>=7500 else ("<IIIB",13)
    def prop(at):
        typ=chr(data[at]);at+=1
        scalars={"Y":"h","C":"?","I":"i","F":"f","D":"d","L":"q"}
        if typ in scalars:
            f="<"+scalars[typ];return struct.unpack_from(f,data,at)[0],at+struct.calcsize(f)
        if typ in "SR":
            n=struct.unpack_from("<I",data,at)[0];at+=4;v=data[at:at+n]
            return v.decode("utf-8",errors="replace") if typ=="S" else v,at+n
        if typ in "fdlibc":
            n,encoded,length=struct.unpack_from("<III",data,at);at+=12
            v=data[at:at+length];at+=length
            if encoded==1:v=zlib.decompress(v)
            elif encoded!=0:raise ValueError("Unknown FBX array encoding")
            return np.frombuffer(v,dtype={"f":"<f4","d":"<f8","l":"<i8","i":"<i4","b":"u1","c":"i1"}[typ],count=n),at
        raise ValueError("Unsupported FBX property "+typ)
    def read(at):
        end,count,_,n=struct.unpack_from(fmt,data,at)
        if not end:return None,at+size
        at+=size;name=data[at:at+n].decode("utf-8");at+=n;ps=[];children=[]
        for _ in range(count):v,at=prop(at);ps.append(v)
        while at<end:
            c,at=read(at)
            if c is None:break
            children.append(c)
        return Node(name,ps,children),end
    out={};at=27
    while at+size<=len(data):
        n,at=read(at)
        if n is None:break
        out[n.name]=n
    return version,out

def properties(node):
    p=node.child("Properties70") if node else None
    return {n.props[0]:n.props[4] if len(n.props)==5 else n.props[4:] for n in p.children if n.name=="P"} if p else {}

def euler(deg,order=0):
    a=np.radians(deg);c=np.cos(a);s=np.sin(a)
    r={"X":np.array([[1,0,0],[0,c[0],-s[0]],[0,s[0],c[0]]]),"Y":np.array([[c[1],0,s[1]],[0,1,0],[-s[1],0,c[1]]]),"Z":np.array([[c[2],-s[2],0],[s[2],c[2],0],[0,0,1]])}
    out=np.eye(3)
    for axis in ["XYZ","XZY","YZX","YXZ","ZXY","ZYX"][int(order)]:out=r[axis]@out
    return out

def rotation(m):
    u,_,v=np.linalg.svd(m[:3,:3]);r=u@v
    if np.linalg.det(r)<0:raise ValueError("Reflected bone basis")
    return r

def quat(m):
    # Stable eigensystem conversion; Godot/glTF order x,y,z,w.
    r=np.asarray(m);k=np.array([[r[0,0]-r[1,1]-r[2,2],r[1,0]+r[0,1],r[2,0]+r[0,2],r[2,1]-r[1,2]], [r[1,0]+r[0,1],r[1,1]-r[0,0]-r[2,2],r[2,1]+r[1,2],r[0,2]-r[2,0]], [r[2,0]+r[0,2],r[2,1]+r[1,2],r[2,2]-r[0,0]-r[1,1],r[1,0]-r[0,1]], [r[2,1]-r[1,2],r[0,2]-r[2,0],r[1,0]-r[0,1],r.trace()]])/3.0
    _,v=np.linalg.eigh(k);q=v[:,-1]
    return -q if q[3]<0 else q

def qmatrix(q):
    x,y,z,w=q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)], [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)], [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])

def transform(p,r=None):
    m=np.eye(4);m[:3,3]=p
    if r is not None:m[:3,:3]=r
    return m

def source_frames(data):
    version,tree=parse_fbx(data);obj={n.props[0]:n for n in tree["Objects"].children if n.props}
    models={i:n for i,n in obj.items() if n.name=="Model"};props={i:properties(n) for i,n in models.items()}
    con=[n.props for n in tree["Connections"].children if n.name=="C"]
    parents={c[1]:c[2] for c in con if c[0]=="OO" and c[1] in models and c[2] in models}
    names={i:n.props[1].split("\x00",1)[0] for i,n in models.items()}
    curves={i:n for i,n in obj.items() if n.name=="AnimationCurve"};cnodes={i:n for i,n in obj.items() if n.name=="AnimationCurveNode"}
    bind={c[1]:(c[2],c[3]) for c in con if c[0]=="OP" and c[1] in cnodes and c[2] in models};tracks={}
    for c in con:
        if c[0]=="OP" and c[1] in curves and c[2] in bind:
            mid,kind=bind[c[2]];curve=curves[c[1]]
            tracks[mid,kind,c[3].split("|")[-1]]=(curve.child("KeyTime").props[0].astype(float)/TICKS,curve.child("KeyValueFloat").props[0])
    first=min(t[0] for t,v in tracks.values());last=max(t[-1] for t,v in tracks.values())
    gs=properties(tree["GlobalSettings"])
    if [gs.get(k) for k in ["UpAxis","UpAxisSign","FrontAxis","FrontAxisSign","CoordAxis","CoordAxisSign"]]!=[1,1,2,1,0,1]:raise ValueError("Unmapped FBX coordinate system")
    unit=float(gs.get("UnitScaleFactor",1))/100.0
    def sample(t,rest=False):
        world={};local={}
        def matrix(i):
            if i in world:return world[i]
            p=props[i]
            for key in ["RotationOffset","RotationPivot","ScalingOffset","ScalingPivot"]:
                if np.linalg.norm(p.get(key,[0,0,0]))>1e-9:raise ValueError("Unsupported FBX pivot")
            values={}
            for kind,default in [("Lcl Translation",[0,0,0]),("Lcl Rotation",[0,0,0]),("Lcl Scaling",[1,1,1])]:
                v=np.array(p.get(kind,default),float)
                if not rest:
                    for axis,k in enumerate("XYZ"):
                        if (i,kind,k) in tracks:
                            times,key=tracks[i,kind,k];v[axis]=np.interp(t,times,key)
                values[kind]=v
            if not np.allclose(values["Lcl Scaling"],1,atol=1e-8):raise ValueError("Nonuniform FBX inheritance not supported")
            r=euler(p.get("PreRotation",[0,0,0]))@euler(values["Lcl Rotation"],p.get("RotationOrder",0))@euler(p.get("PostRotation",[0,0,0])).T
            m=transform(values["Lcl Translation"]*unit,r);local[i]=m
            world[i]=matrix(parents[i])@m if i in parents else m
            return world[i]
        for i in models:matrix(i)
        return {names[i]:world[i] for i in models},{names[i]:local[i] for i in models}
    times=np.linspace(first,last,round((last-first)*30)+1)
    # Every baked time is an actual key time. No FBX tangent interpolation claim.
    for t in times:
        if any(np.ptp(values)>1e-9 and np.min(np.abs(ts-t))>1e-6 for ts,values in tracks.values()):raise ValueError("Bake time missing from a varying source curve")
    rest,rest_local=sample(first,True);frames=[sample(t)[0] for t in times]
    return {"version":version,"unit":unit,"first":float(first),"times":times-first,"rest":rest,"rest_local":rest_local,"frames":frames,"names":list(rest),"parents":{names[i]:names.get(parents.get(i)) for i in models}}

def target_rig():
    path=WORKSPACE/"assets/characters/body.glb";raw=path.read_bytes();n=struct.unpack_from("<I",raw,12)[0];g=json.loads(raw[20:20+n])
    nodes=g["nodes"];parents={c:i for i,v in enumerate(nodes) for c in v.get("children",[])};world={};local={}
    def matrix(i):
        if i in world:return world[i]
        v=nodes[i];q=v.get("rotation",[0,0,0,1]);s=v.get("scale",[1,1,1]);m=transform(v.get("translation",[0,0,0]),qmatrix(q)@np.diag(s));local[i]=m
        world[i]=matrix(parents[i])@m if i in parents else m;return world[i]
    for i in range(len(nodes)):matrix(i)
    index={v["name"]:i for i,v in enumerate(nodes) if "name" in v};joints=g["skins"][0]["joints"]
    if len(joints)!=87 or any(s["joints"]!=joints for s in g["skins"]):raise ValueError("Unexpected source rig")
    return {"sha256":hashlib.sha256(raw).hexdigest(),"names":list(MAP),"local":{n:local[index[n]] for n in MAP},"world":{n:world[index[n]] for n in MAP},"parents":{n:nodes[parents[index[n]]].get("name") for n in MAP},"indices":{n:joints.index(index[n]) for n in MAP}}

def foot_points(m):
    # Original Character motion_parameters: ankle .085, heel .065, ball .11.
    return np.array([(m@np.array([0,-.085,-.065,1]))[:3],(m@np.array([0,-.085,.11,1]))[:3]])

def round_list(a):return np.asarray(a).round(10).tolist()

def generate(name,src,tgt):
    times=src["times"];world=src["frames"];hip="mixamorig:Hips";rhip=src["rest"][hip];h=np.array([w[hip][:3,3] for w in world])
    forward=np.array([rotation(w[hip])@np.array([0,0,1]) for w in world]);yaw=np.unwrap(np.arctan2(forward[:,0],forward[:,2]));turn=yaw-yaw[0]
    ratio=[]
    for side in ["L","R"]:
        st=[src["rest"]["mixamorig:"+MAP[n]][:3,3] for n in ["thigh"+side,"shin"+side,"foot"+side]]
        a=np.linalg.norm(st[1]-st[0])+np.linalg.norm(st[2]-st[1])
        b=np.linalg.norm(tgt["local"]["shin"+side][:3,3])+np.linalg.norm(tgt["local"]["foot"+side][:3,3]);ratio.append(b/a)
    scale=float(np.mean(ratio));detrend=h-h[0]-np.outer(times/times[-1],h[-1]-h[0]);detrend[:,1]=h[:,1]-rhip[1,3]
    output=[];global_target=[];last_q={};raw=[];candidates=[]
    for frame,w in enumerate(world):
        inv=euler([0,-math.degrees(turn[frame]),0]);global_r={};local_pose=[];target_w={}
        for n in tgt["names"]:
            s="mixamorig:"+MAP[n];r=inv@rotation(w[s])@rotation(src["rest"][s]).T@rotation(tgt["world"][n]);global_r[n]=r
            parent=tgt["parents"][n];lr=global_r[parent].T@r if parent in global_r else r
            p=tgt["local"][n][:3,3].copy()
            if n=="hips":p+=inv@detrend[frame]*scale
            q=quat(lr)
            if n in last_q and np.dot(q,last_q[n])<0:q=-q
            last_q[n]=q
            local_pose.append({"position":round_list(p),"rotation":round_list(q),"scale":[1,1,1]})
            m=transform(p,lr);target_w[n]=target_w[parent]@m if parent in target_w else m
        visual=transform([0,0,0],euler([0,math.degrees(turn[frame]),0]));global_target.append({n:visual@m for n,m in target_w.items()})
        output.append({"time":float(times[frame]),"root_yaw":float(turn[frame]),"source_hips_position_m":round_list(h[frame]),"source_hips_rotation":round_list(quat(rotation(w[hip]))),"lower":local_pose})
        raw.append({"time":float(times[frame]),"world_positions_m":[round_list(w[n][:3,3]) for n in src["names"]],"world_rotations":[round_list(quat(rotation(w[n]))) for n in src["names"]]})
    source_contacts=[];target_contacts=[];stats={};anchors={}
    for side,label in [("L","Left"),("R","Right")]:
        source_toes=[np.array([w["mixamorig:"+label+n][:3,3] for w in world]) for n in ["ToeBase","Toe_End"]]
        floor=min(p[:,1].min() for p in source_toes);contact=np.zeros(len(times),bool)
        for p in source_toes:contact|=(p[:,1]<=floor+.03)&(np.linalg.norm(np.gradient(p[:,[0,2]],times,axis=0),axis=1)<=.25)
        points=np.array([foot_points(w["foot"+side]) for w in global_target]);low=np.min(points[:,:,1],axis=1)
        velocity=np.min(np.linalg.norm(np.gradient(points[:,:,[0,2]],times,axis=0),axis=2),axis=1)
        candidate=(low<=low.min()+.03)&(velocity<=.25)
        slips=[];anchor=None;old=False
        for i,on in enumerate(candidate):
            if on and not old:anchor=points[i,int(points[i,:,1].argmin())].copy()
            if on:slips.append(float(np.min(np.linalg.norm(points[i,:,:]-anchor,axis=1))))
            old=bool(on)
        stats[side]={"source_candidate_frames":int(contact.sum()),"target_candidate_frames":int(candidate.sum()),"minimum_sole_y_m":float(low.min()),"maximum_candidate_sole_slide_m":max(slips,default=0.0)}
        source_contacts.append(contact);target_contacts.append(candidate)
    for i,frame in enumerate(output):frame["source_contact_candidate"]=[bool(c[i]) for c in source_contacts];frame["target_contact_candidate"]=[bool(c[i]) for c in target_contacts]
    clip_id="mixamo_"+Path(name).stem.replace(" ","_")
    raw_result={"source_file":name,"names":src["names"],"parents":src["parents"],"rest_global_positions_m":[round_list(src["rest"][n][:3,3]) for n in src["names"]],"frames":raw}
    return {"id":clip_id,"source_file":name,"duration":float(times[-1]),"loop":False,"actual_turn_radians":float(turn[-1]),"root_tracks":[],"hip_sway_policy":"unit .01; remove only net XZ drift baseline; preserve scaled nonlinear pelvis sway and rest-relative Y; projected Hips yaw stored separately and removed once from lower pose","leg_scale":ratio,"source_contact_labels":"inferred toe-height/speed candidates, not authored labels","target_contact_labels":"recomputed target heel/ball height/speed candidates, not production FootPlant labels","quality":stats,"frames":output},raw_result

def animation_text(clip,names):
    lines=['[gd_resource type="Animation" format=3]','', '[resource]',f'resource_name = "{clip["id"]}"',f'length = {clip["duration"]:.10f}','loop_mode = 0']
    track=0
    for bone,n in enumerate(names):
        if clip.get("writes_hips") is False and n=="hips":continue
        kinds=["rotation_3d"]+(["position_3d"] if n=="hips" else [])
        for kind in kinds:
            values=[]
            for f in clip["frames"]:
                p=f["lower"][bone]["rotation" if kind=="rotation_3d" else "position"]
                # Godot 4.7 Animation::_set: 3-D tracks use flat packed keys,
                # [time,transition,x,y,z,(w)] rather than value-track dictionaries.
                values.extend([f'{f["time"]:.10f}',"1"]+[f"{x:.10f}" for x in p])
            lines.extend([f'tracks/{track}/type = "{kind}"',f'tracks/{track}/path = NodePath("Skeleton3D:{n}")',f'tracks/{track}/interp = 1',f'tracks/{track}/loop_wrap = false',f'tracks/{track}/keys = PackedFloat32Array({", ".join(values)})'])
            track+=1
    return "\n".join(lines)+"\n"

def main():
    if WORKSPACE.resolve()!=Path(r"H:\GDP\inkwave\splatink").resolve():raise ValueError("Unexpected workspace")
    before=ARCHIVE.stat();payload=ARCHIVE.read_bytes()
    if hashlib.sha256(payload).hexdigest()!=ARCHIVE_SHA:raise ValueError("Original pack SHA mismatch")
    tgt=target_rig();out=WORKSPACE/"assets/animation/experiments/mixamo";cache=WORKSPACE/".tools/mixamo-turn-prototype"
    for p in [out,cache]:
        p.mkdir(parents=True,exist_ok=True)
        if p.is_symlink() or p.resolve().is_relative_to(WORKSPACE.resolve()) is False:raise ValueError("Unsafe output directory")
    (cache/".gdignore").write_text("\n",encoding="utf-8")
    clips=[];raw=[]
    with zipfile.ZipFile(ARCHIVE) as z:
        for name in FILES:
            member=PurePosixPath(name)
            if member.is_absolute() or ".." in member.parts or ":" in name:raise ValueError("Unsafe member")
            data=z.read(name);src=source_frames(data);clip,ref=generate(name,src,tgt)
            clip["source_sha256"]=hashlib.sha256(data).hexdigest();clip["source_bones"]=len(src["names"]);clip["source_unit_to_m"]=src["unit"]
            clip["variants"]={}
            for fixed in [False,True]:
                variant=correct(clip,tgt,(transform,qmatrix,quat,foot_points,round_list),fixed)
                clip["variants"][variant["mode"]]=variant
                (out/(variant["id"]+".tres")).write_text(animation_text(variant,tgt["names"]),encoding="utf-8")
            clips.append(clip);raw.append(ref);(out/(clip["id"]+".tres")).write_text(animation_text(clip,tgt["names"]),encoding="utf-8")
    result={"version":1,"experimental":True,"default_enabled":False,"archive_sha256":ARCHIVE_SHA,"target_body_sha256":tgt["sha256"],"source_rig_bones":65,"target_rig_bones":87,"fps":30,"names":tgt["names"],"target_indices":tgt["indices"],"target_parents":tgt["parents"],"target_rest":[{"position":round_list(tgt["local"][n][:3,3]),"rotation":round_list(quat(rotation(tgt["local"][n]))),"scale":[1,1,1]} for n in tgt["names"]],"method":"global rest-basis delta, parent-local reconstruction, target fixed segment offsets; removed yaw/drift preserved as metadata; no production root motion","clips":clips}
    (out/"turns.json").write_text(json.dumps(result,separators=(",",":")),encoding="utf-8")
    (cache/"raw_source.json").write_text(json.dumps(raw,separators=(",",":")),encoding="utf-8")
    after=ARCHIVE.stat()
    if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns):raise RuntimeError("Original archive modified")
    print(json.dumps({"target_sha256":tgt["sha256"],"clips":[{**{k:c[k] for k in ["id","duration","actual_turn_radians","quality"]},"variants":{k:v["quality"] for k,v in c["variants"].items()}} for c in clips]},indent=2))

if __name__=="__main__":main()
