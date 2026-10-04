import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const root=path.join(project,'.tools/mm-native/source');
const header=path.join(root,'src/mm_animation_library.h');
const implementation=path.join(root,'src/mm_animation_library.cpp');
let h=fs.readFileSync(header,'utf8').replace(/\r\n/g,'\n');
let c=fs.readFileSync(implementation,'utf8').replace(/\r\n/g,'\n');
if(h.includes('configure_external_database'))throw Error('Bridge already applied; prepare a clean isolated copy first');
const replace=(s,from,to)=>{if(s.split(from).length!==2)throw Error(`Patch anchor changed: ${from.slice(0,60)}`);return s.replace(from,to);};
h=replace(h,'    int64_t get_dim_count() const;',`    // Splatink external pose provider. The native library owns exact search;
    // gameplay owns normalization, trajectory and authoritative world movement.
    Error configure_external_database(const PackedFloat32Array& p_data,
        const PackedFloat32Array& p_weights, const PackedInt32Array& p_animation_indices,
        const PackedFloat32Array& p_times, const PackedInt32Array& p_offsets);
    Dictionary query_normalized_vector(const PackedFloat32Array& p_query, int p_current_pose = -1);
    int64_t get_dim_count() const;`);
h=replace(h,'    std::vector<float> _dimension_weights_cache;','    std::vector<float> _dimension_weights_cache;\n    PackedFloat32Array _external_dimension_weights;');
c=replace(c,'    _invalidate_animation_metadata_cache();','    _external_dimension_weights.clear();\n    _invalidate_animation_metadata_cache();');
c=replace(c,'int64_t MMAnimationLibrary::get_dim_count() const {','int64_t MMAnimationLibrary::get_dim_count() const {\n    if (!_external_dimension_weights.is_empty()) return _external_dimension_weights.size();');
c=replace(c,'void MMAnimationLibrary::_refresh_dimension_weights_cache() {',`void MMAnimationLibrary::_refresh_dimension_weights_cache() {
    if (!_external_dimension_weights.is_empty()) {
        const int count = _external_dimension_weights.size();
        _dimension_weights_cache.assign(_external_dimension_weights.ptr(), _external_dimension_weights.ptr() + count);
        return;
    }`);
c=replace(c,'    float pose_cost = 0.f;\n    int start_frame_index = p_pose_index * p_query.size();',`    float pose_cost = 0.f;
    int start_frame_index = p_pose_index * p_query.size();
    if (!_external_dimension_weights.is_empty()) {
        for (int dimension = 0; dimension < p_query.size(); ++dimension) {
            const float delta = motion_data[start_frame_index + dimension] - p_query[dimension];
            pose_cost += delta * delta * _external_dimension_weights[dimension];
        }
        return pose_cost;
    }`);
const api=`
Error MMAnimationLibrary::configure_external_database(const PackedFloat32Array& p_data,
    const PackedFloat32Array& p_weights, const PackedInt32Array& p_animation_indices,
    const PackedFloat32Array& p_times, const PackedInt32Array& p_offsets) {
    const int dimensions = p_weights.size();
    const int poses = p_times.size();
    const TypedArray<StringName> names = get_animation_list();
    if (dimensions <= 0 || dimensions > 256 || poses <= 0 || poses > 2000000 ||
        p_data.size() != int64_t(poses) * dimensions || p_animation_indices.size() != poses ||
        names.is_empty() || p_offsets.size() != names.size() || p_offsets[0] != 0)
        return ERR_INVALID_DATA;
    for (int dimension = 0; dimension < dimensions; ++dimension)
        if (!std::isfinite(p_weights[dimension]) || p_weights[dimension] < 0.0f || p_weights[dimension] > 1.0e6f) return ERR_INVALID_DATA;
    for (int64_t value = 0; value < p_data.size(); ++value)
        if (!std::isfinite(p_data[value]) || std::abs(p_data[value]) > 1.0e10f) return ERR_INVALID_DATA;
    for (int animation = 0; animation < names.size(); ++animation) {
        const int start = p_offsets[animation];
        const int end = animation + 1 < names.size() ? p_offsets[animation + 1] : p_data.size();
        if (start < 0 || end <= start || end > p_data.size() || start % dimensions || end % dimensions)
            return ERR_INVALID_DATA;
        Ref<Animation> clip = get_animation(names[animation]);
        if (clip.is_null()) return ERR_INVALID_DATA;
        for (int pose = start / dimensions; pose < end / dimensions; ++pose)
            if (p_animation_indices[pose] != animation || !std::isfinite(p_times[pose]) ||
                p_times[pose] < 0.0f || p_times[pose] > clip->get_length()) return ERR_INVALID_DATA;
    }
    motion_data = p_data.duplicate();
    _external_dimension_weights = p_weights.duplicate();
    db_anim_index = p_animation_indices.duplicate();
    db_time_index = p_times.duplicate();
    db_pose_offset = p_offsets.duplicate();
    features.clear();
    node_indices.clear();
    _kd_tree.reset();
    _dimension_weights_cache.clear();
    _invalidate_animation_metadata_cache();
    return OK;
}

Dictionary MMAnimationLibrary::query_normalized_vector(const PackedFloat32Array& p_query, int p_current_pose) {
    Dictionary result;
    result["valid"] = false;
    if (_external_dimension_weights.is_empty() || p_query.size() != get_dim_count() ||
        p_current_pose < -1 || p_current_pose >= db_time_index.size()) {
        result["error"] = "Invalid database, dimensions or continuation pose";
        return result;
    }
    for (int dimension = 0; dimension < p_query.size(); ++dimension)
        if (!std::isfinite(p_query[dimension]) || std::abs(p_query[dimension]) > 1.0e10f) {
            result["error"] = "Query contains nonfinite values";
            return result;
        }
    _last_query_nodes_visited = 0;
    _last_query_built_kd_tree = false;
    _last_kd_tree_build_microseconds = 0;
    const auto started = std::chrono::steady_clock::now();
    const MMQueryOutput output = _search_exact_contiguous(p_query);
    if (output.matched_pose_index < 0) return result;
    result["valid"] = true;
    result["matched_pose_index"] = output.matched_pose_index;
    result["animation_match"] = output.animation_match;
    result["time_match"] = output.time_match;
    result["cost"] = output.cost;
    result["continuation_cost"] = p_current_pose >= 0 ? _compute_feature_costs(p_current_pose,p_query,nullptr) : -1.0f;
    result["poses_evaluated"] = _last_query_nodes_visited;
    result["query_microseconds"] = int64_t(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-started).count());
    return result;
}

`;
c=replace(c,'void MMAnimationLibrary::_bind_methods() {',api+`void MMAnimationLibrary::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure_external_database", "data", "weights", "animation_indices", "times", "offsets"), &MMAnimationLibrary::configure_external_database);
    ClassDB::bind_method(D_METHOD("query_normalized_vector", "query", "current_pose"), &MMAnimationLibrary::query_normalized_vector, DEFVAL(-1));`);
fs.writeFileSync(header,h);
fs.writeFileSync(implementation,c);
console.log('Applied external normalized query API; original native exact-search function unchanged');
