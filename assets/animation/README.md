# Original character motion matching

`tools/export_motion_database.mjs` samples the 42 original INKWAVE locomotion clips (six cycles for each of seven weapon holds) from `body.glb` into 1,638 poses with 63 features. It preserves the 87-bone rig, clothing, hair and original character shape. Source animations are in-place: future root trajectories are explicitly tagged from source movement speeds rather than falsely claiming measured root motion.

The provider normalizes seven bone positions/velocities and seven future trajectory samples, searches the relevant weapon bucket, favours continuation, limits rapid switching and changes the real `AnimationNodeAnimation` + `AnimationNodeTimeSeek` inputs. A quaternion-log inertializer preserves the previous output pose and velocity while critically damped offsets settle onto the new clip. Air, squid, weapon aim and action layers remain in the original `AnimationTree`.

Scene graph: `InkAvatar/AvatarAnimationTree`: `MotionClip -> MotionTime -> MotionSelection -> Air -> Aim -> Action -> output`. `Locomotion` remains the selectable fallback branch. `InkAvatar.motion_matching` toggles the provider; `motion_state` reports database size, matched clip/frame, query count, transition count and cost. Gameplay supplies actual and desired world velocity, desired world facing and `is_local`. The actor keeps physics authority; no root displacement is applied.

The design follows the project's rooftop-bird-team trajectory/pose query and inertialization approach. Its Windows-only GDExtension binary and incompatible 24-bone animation database are not dependencies. These GDScript/data files run on Godot's Windows, macOS, iOS and Android runtimes. Device performance still requires on-device measurements.

Verification: root runs `tools/verify_motion_matching.gd` with a 30 second watchdog. It checks real clip changes, query sensitivity to bone pose, seven weapon families, inertia finiteness and retained action/air/squid layers. Visual transition quality and frame cost require real gameplay capture; a passing functional contract is not a visual or performance guarantee.

C# hosts can control this GDScript node without a second animation implementation:

```csharp
avatar.Set("motion_matching", true);
avatar.Call("animate", delta, new Godot.Collections.Dictionary {
    ["velocity"] = actualVelocity,
    ["desired_velocity"] = desiredVelocity,
    ["desired_facing"] = facing,
    ["grounded"] = grounded,
    ["form"] = "kid",
    ["is_local"] = true
});
var match = (Godot.Collections.Dictionary)avatar.Get("motion_state");
```
