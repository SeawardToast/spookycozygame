shader_type canvas_item;

uniform float shake_intensity = 1.0;
uniform float shake_speed = 20.0;
uniform float fall_progress = 0.0; // 0 = upright, 1 = fully fallen
uniform vec2 fall_direction = vec2(1.0, 0.0); // horizontal direction tree falls in (x,y)

void vertex() {
    vec2 shake = vec2(0.0);

    // Shake effect (like your current code)
    if (VERTEX.y < 0.0) {
        shake.x = sin(TIME * shake_speed + VERTEX.y) * shake_intensity;
    }

    vec2 pos = VERTEX.xy + shake;

    // Fall effect
    // Rotate the vertex around the base (y = 0) by an angle proportional to fall_progress
    float theta = fall_progress * (PI / 2.0); // 90 degrees max fall
    vec2 base = vec2(0.0, 0.0); // pivot at bottom of tree
    vec2 dir = pos - base;

    // 2D rotation
    float cos_t = cos(theta);
    float sin_t = sin(theta);
    vec2 rotated;
    rotated.x = dir.x * cos_t - dir.y * sin_t;
    rotated.y = dir.x * sin_t + dir.y * cos_t;

    VERTEX.xy = base + rotated;
}
