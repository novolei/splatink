# MM editor panel ownership cleanup

The first `splatlower1` Windows libraries passed real native-query, seven-weapon lower-body mask, motion continuity and source aiming contracts. Editor/import shutdown alone consistently leaked Control nodes, fonts/text and rendering RIDs.

The original `MMEditorPlugin` owns a `memnew(MMEditor)` control. Its destructor removes that control from the bottom panel but does not release it. Godot's official `remove_control_from_bottom_panel` API explicitly requires manual deletion after removal. The narrow isolated-source patch calls `memdelete(_editor)` and clears the pointer after the existing detach. This runs only during editor plugin teardown; database, query, animation and gameplay code are unchanged. Reference projects remain read-only.

Official ownership documentation: https://docs.godotengine.org/en/stable/classes/class_editorplugin.html#class-editorplugin-method-remove-control-from-bottom-panel

Previous diagnostic binary SHA-256:

| Mode | Previous SHA-256 |
| --- | --- |
| Windows debug | `3a20de08a171e078279fc8500db395ec517e271bb6d610195666f8dba2ed3648` |
| Windows release | `109db398ec7f54bebe29e87eaa6dcdcac3813ef85315d4859c20cf9c9675786d` |

The replacement binaries and updated complete-source archive are identified by current addon provenance and source-archive.json. Root must run fresh editor import with stdout/stderr capture as well as runtime contracts; successful compilation alone does not validate leak cleanup.
