# Windows checkpoint uses the exact frozen prebuilt godot-cpp static bindings.
# Full upstream SConstruct remains in source/ for macOS compilation from source.
from pathlib import Path
from SCons.Script import ARGUMENTS, Environment, Default

mode = ARGUMENTS.get('target', 'template_debug')
if mode not in ('template_debug', 'template_release'):
    raise ValueError('Only template_debug/template_release supported')
suffix = 'debug' if mode == 'template_debug' else 'release'
env = Environment(tools=['default'], TARGET_ARCH='amd64', MSVC_TARGET_ARCH='amd64')
env.Append(CPPPATH=['source/src', 'source/godot-cpp/include', 'source/godot-cpp/gen/include'])
env.Append(CPPDEFINES=['TYPED_METHOD_BIND', 'NOMINMAX', 'WINDOWS_ENABLED', 'THREADS_ENABLED', 'GDEXTENSION', 'NDEBUG'])
if suffix == 'debug': env.Append(CPPDEFINES=['DEBUG_ENABLED'])
env.Append(CCFLAGS=['/std:c++17', '/Zc:__cplusplus', '/EHsc', '/MT', '/O2', '/utf-8'])
env.Append(LINKFLAGS=['/WX'])
env.Append(LIBS=[str(Path('cache/bindings') / f'libgodot-cpp.windows.template_{suffix}.x86_64.lib')])
objects=[]
for pattern in ['src/*.cpp', 'src/algo/*.cpp', 'src/editor/*.cpp', 'src/features/*.cpp', 'src/math/*.cpp', 'src/modifiers/*.cpp', 'src/synchronizers/*.cpp', 'src/gen/doc_data.gen.cpp']:
    for source in sorted(Path('source').glob(pattern)):
        relative=source.relative_to('source').with_suffix('.obj')
        objects += env.SharedObject(str(Path('cache/objects') / suffix / relative), str(source))
library=env.SharedLibrary(f'publish/bin/windows/libgdmotionmatching.windows.template_{suffix}.x86_64.splatlower1.dll',objects)
Default(library)
