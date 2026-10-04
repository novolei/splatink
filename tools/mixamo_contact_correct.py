"""Experiment-only contact pass; input/source rotations remain separately available.

This is a synthesized offline correction, not an authored Mixamo action or a new
production foot solver. Contacts are inferred from geometry/velocity. Full-weight
constraints and every reach clamp are exported so QA can measure actual FK.
"""
import math
import numpy as np


def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x*x*(3.0-2.0*x)


def frame_axis(v):
    v = v/np.linalg.norm(v)
    h = np.array([1.0, 0.0, 0.0])-v*v[0]
    h = h/np.linalg.norm(h)
    return np.stack([v, h, np.cross(v, h)])


def fk(poses, names, parents, transform, qmatrix, yaw):
    world = {}
    root = transform([0, 0, 0], np.array([[math.cos(yaw), 0, math.sin(yaw)], [0, 1, 0], [-math.sin(yaw), 0, math.cos(yaw)]]))
    for n, p in zip(names, poses):
        local = transform(p["position"], qmatrix(p["rotation"]))
        parent = parents[n]
        world[n] = world[parent]@local if parent in world else root@local
    return world


def correct(clip, target, math_api, fixed_hips=False):
    """Correct sole endpoints at original duration; never time-warps the yaw curve."""
    transform, qmatrix, quat, foot_points, round_list = math_api
    names = target["names"]
    index = {n:i for i,n in enumerate(names)}
    count = len(clip["frames"])
    times = np.array([f["time"] for f in clip["frames"]])
    poses = [[{k:list(v) for k,v in p.items()} for p in f["lower"]] for f in clip["frames"]]
    if fixed_hips:
        rest = target["local"]["hips"]
        for frame in poses:
            frame[0] = {"position":round_list(rest[:3,3]), "rotation":round_list(quat(rest[:3,:3])), "scale":[1,1,1]}
    yaw = np.zeros(count) if fixed_hips else np.array([f["root_yaw"] for f in clip["frames"]])
    raw_world = [fk(p,names,target["parents"],transform,qmatrix,y) for p,y in zip(poses,yaw)]
    contacts = np.zeros((count,2), bool)
    weights = np.zeros((count,2))
    anchors = np.zeros((count,2,3))
    points = np.zeros((count,2), int)
    windows = []
    sole_local = [np.array([0.0,-.085,-.065]),np.array([0.0,-.085,.11])]
    for side,s in enumerate(["L","R"]):
        p = np.array([foot_points(w["foot"+s]) for w in raw_world])
        velocity = np.linalg.norm(np.gradient(p[:,:,[0,2]],times,axis=0),axis=2)
        low = p[:,:,1].min(axis=1)
        # Recomputed on this target/mode, and intersected with source evidence.
        # A filename or a stance-like pose alone never supplies a contact label.
        source = np.array([f["source_contact_candidate"][side] for f in clip["frames"]])
        candidate = (low<=low.min()+.03)&(velocity.min(axis=1)<=.25)&source
        begin = None
        for i in range(count+1):
            active = i<count and candidate[i]
            if active and begin is None:begin=i
            if not active and begin is not None:
                end = i-1
                if end-begin>=4:
                    point = int(p[begin,:,1].argmin())
                    anchor = p[begin,point].copy()
                    anchor[1] = 0.0  # flat preview floor; no production ground query
                    windows.append({"leg":side,"start":begin,"end":end,"sole_point":point,"anchor":round_list(anchor)})
                    for j in range(begin,end+1):
                        contacts[j,side]=True
                        # Three original samples (0.1s) acquire/release the offline
                        # constraint; full-weight samples are measured separately.
                        weights[j,side]=float(smoothstep(min((j-begin)/3.0,(end-j)/3.0)))
                        anchors[j,side]=anchor
                        points[j,side]=point
                begin=None
    last_quat = {}
    frames=[]
    maximum_drop=0.0
    maximum_reach_clamp=0.0
    maximum_contact_error=0.0
    full_samples=0
    for i in range(count):
        pose=poses[i]
        world=fk(pose,names,target["parents"],transform,qmatrix,yaw[i])
        endpoints=[]
        for side,s in enumerate(["L","R"]):
            foot=world["foot"+s]
            desired=anchors[i,side]-foot[:3,:3]@sole_local[points[i,side]]
            endpoint=foot[:3,3]*(1.0-weights[i,side])+desired*weights[i,side]
            endpoints.append(endpoint)
        # Only the nine-bone preview may lower its internal pelvis. The fixed
        # authority eight-bone mode reports unreachable targets rather than
        # secretly altering hips/world root or moving the retained upper body.
        drop=0.0
        if not fixed_hips:
            for side,s in enumerate(["L","R"]):
                if weights[i,side]<=0.0:continue
                origin=world["thigh"+s][:3,3]
                a=np.linalg.norm(target["local"]["shin"+s][:3,3])
                b=np.linalg.norm(target["local"]["foot"+s][:3,3])
                reach=(a+b)*.9995
                horizontal=np.linalg.norm((origin-endpoints[side])[[0,2]])
                vertical=math.sqrt(max(0.0,reach*reach-horizontal*horizontal))
                drop=max(drop,origin[1]-endpoints[side][1]-vertical)
            drop=min(max(0.0,drop),.12)
            pose[0]["position"][1]-=drop
            world=fk(pose,names,target["parents"],transform,qmatrix,yaw[i])
        maximum_drop=max(maximum_drop,drop)
        for side,s in enumerate(["L","R"]):
            if weights[i,side]<=0.0:continue
            origin=world["thigh"+s][:3,3]
            desired=endpoints[side]
            vector=desired-origin
            distance=np.linalg.norm(vector)
            direction=vector/distance
            a_vec=target["local"]["shin"+s][:3,3]
            b_vec=target["local"]["foot"+s][:3,3]
            a=np.linalg.norm(a_vec);b=np.linalg.norm(b_vec)
            distance_clamped=np.clip(distance,abs(a-b)+.001,(a+b)*.9995)
            maximum_reach_clamp=max(maximum_reach_clamp,abs(distance-distance_clamped))
            animated_knee=world["shin"+s][:3,3]-origin
            plane=animated_knee-direction*np.dot(animated_knee,direction)
            if np.linalg.norm(plane)<1e-7:
                plane=np.array([0.0,0.0,1.0])-direction*direction[2]
            plane/=np.linalg.norm(plane)
            cos_a=np.clip((a*a+distance_clamped*distance_clamped-b*b)/(2*a*distance_clamped),-1.0,1.0)
            knee=origin+direction*a*cos_a+plane*a*math.sqrt(max(0.0,1-cos_a*cos_a))
            endpoint=origin+direction*distance_clamped
            h=np.cross(plane,direction);h/=np.linalg.norm(h)
            axis=(knee-origin)/a
            up=np.stack([axis,h,np.cross(axis,h)],axis=1)@frame_axis(a_vec)
            low_axis=(endpoint-knee)/b
            low=np.stack([low_axis,h,np.cross(low_axis,h)],axis=1)@frame_axis(b_vec)
            foot_rotation=world["foot"+s][:3,:3]
            parent=world["hips"][:3,:3]
            pose[index["thigh"+s]]["rotation"]=round_list(quat(parent.T@up))
            pose[index["shin"+s]]["rotation"]=round_list(quat(up.T@low))
            pose[index["foot"+s]]["rotation"]=round_list(quat(low.T@foot_rotation))
        world=fk(pose,names,target["parents"],transform,qmatrix,yaw[i])
        errors=[]
        for side,s in enumerate(["L","R"]):
            actual=foot_points(world["foot"+s])[points[i,side]]
            error=float(np.linalg.norm(actual-anchors[i,side])) if contacts[i,side] else 0.0
            errors.append(error)
            if weights[i,side]>=.999:
                maximum_contact_error=max(maximum_contact_error,error);full_samples+=1
        for n,p in zip(names,pose):
            q=np.array(p["rotation"])
            if n in last_quat and np.dot(last_quat[n],q)<0:q=-q
            p["rotation"]=round_list(q);last_quat[n]=q
        frames.append({"time":float(times[i]),"root_yaw":float(yaw[i]),"lower":pose,"contact_candidate":contacts[i].tolist(),"contact_weight":weights[i].tolist(),"sole_point":points[i].tolist(),"sole_anchor":round_list(anchors[i]),"contact_error_m":errors,"hip_drop_m":drop})
    angular=[];hip_steps=[]
    for i in range(1,count):
        for a,b in zip(frames[i-1]["lower"],frames[i]["lower"]):
            dot=min(1.0,abs(float(np.dot(a["rotation"],b["rotation"]))))
            angular.append(2*math.acos(dot))
        hip_steps.append(float(np.linalg.norm(np.array(frames[i]["lower"][0]["position"])-frames[i-1]["lower"][0]["position"])))
    return {"id":clip["id"]+("_fixed8_contact" if fixed_hips else "_source9_contact"),"duration":clip["duration"],"loop":False,"mode":"fixed_authority_leg8" if fixed_hips else "source_yaw_pelvis9","synthesized_contact_pass":True,"root_tracks":[],"writes_hips":not fixed_hips,"contact_threshold_m":.03,"contact_speed_threshold_m_s":.25,"contact_acquisition_release_s":.1,"contact_labels":"inferred target sole and source toe candidates; three-sample synthesized constraint ramps; not authored Mixamo labels","windows":windows,"quality":{"full_contact_samples":full_samples,"maximum_full_contact_error_m":maximum_contact_error,"maximum_pelvis_drop_m":maximum_drop,"maximum_reach_clamp_m":maximum_reach_clamp,"maximum_30hz_local_rotation_step_rad":max(angular,default=0.0),"maximum_30hz_hip_step_m":max(hip_steps,default=0.0)},"frames":frames}
