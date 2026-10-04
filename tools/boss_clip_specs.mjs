// Shared source Boss clip/event sampling contract. These clocks mirror the
// final BossBrain._start move records, including its overrides of MOVES.act.
import {MOVES,PACE,MIN_TELE,HZ,chargeTime} from '../../src/boss/bossHazards.js';

export function bossMoveSpec(attack,phase=1){
  const source=MOVES[attack],pace=PACE[phase];
  const durations=[Math.max(MIN_TELE,source.tele*pace),source.act*pace,source.rec*pace];
  let params={};
  if(attack==='slam'){
    durations[1]=1.2;
    params={rings:phase>=3?[0,.6]:phase>=2?[0,.9]:[0]};
  }else if(attack==='barrage'){
    const n=[0,4,5,7][phase];
    params={sx:0,sy:5.4,sz:-.6,b:Array.from({length:n},(_,i)=>[0,0,0,durations[0]+i*HZ.barrelGap])};
    durations[1]=(n-1)*HZ.barrelGap+HZ.barrelFlight+.1;
  }else if(attack==='charge'){
    // Representative 20m lane. Runtime maps the normalized charge phase onto
    // its actual raycast lane; the source speed and stun clocks stay explicit.
    params={x:0,y:0,z:0,yaw:0,L:20,wall:1,v:HZ.chargeSpeed[phase],stun:1};
    durations[1]=chargeTime(params);
    durations[2]=HZ.stun[phase];
  }else if(attack==='crablets'){
    params={n:phase>=3?5:3};
  }else if(attack==='sweep'){
    const span=[0,1.9,2.2,2.5][phase];
    params={ox:0,oy:2.3,oz:3.3,y:0,a0:-span/2,a1:span/2,c:0};
  }else if(attack==='frenzy'){
    params={x:0,y:0,z:0,rot0:0,spin:1,stun:1};
  }
  return {durations,params};
}

export function buildBossClipSpecs(){
  const clips=[];
  for(const phase of [1,2,3]){
    const prefix=phase===1?'':`p${phase}_`;
    for(const[name,duration,state,loop]of [
      ['idle',4,{},true],['run',1.5,{speed:3},true],
      ['intro',3.4,{move:'intro',phaseDur:3.4},false],
      ['roar',1.9,{move:'roar',phaseDur:1.9},false],
      ['stun',3,{stunned:true,phaseDur:3},true],['dead',6,{dead:true},false]
    ])clips.push({name:prefix+name,key:'boss_'+prefix+name,duration,state:{phase,...state},loop});
    for(const attack of Object.keys(MOVES)){
      const activePhase=attack==='frenzy'?3:phase;
      const spec=bossMoveSpec(attack,activePhase);
      for(let i=0;i<3;i++){
        const phaseName=['tele','act','rec'][i];
        clips.push({name:`${prefix}${attack}_${phaseName}`,key:`boss_${prefix}${attack}_${phaseName}`,
          duration:spec.durations[i],loop:false,state:{move:attack,movePhase:phaseName,
            phaseDur:spec.durations[i],phase:activePhase,params:spec.params,
            _capture_durations:spec.durations}});
      }
    }
  }
  return clips;
}
