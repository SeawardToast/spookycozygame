shader_type canvas_item;

uniform float hit_intensity = 0.0;   // how violently the rock shakes
uniform float break_progress = 0.0;  // 0 = intact, 1 = fully broken
uniform float hit_speed = 40.0;      // frequency of shake
uniform vec2 break_direction = vec2(1.0, -1.0); // direction rock fragments “fly”

void vertex() {
    vec2 pos = VERTEX.xy;

    // 1. Hit shake (small jitter for pickaxe impact)
    pos += vec2(
        sin(TIME * hit_speed + VERTEX.y * 0.5) * hit_intensity,
        cos(TIME * hit_speed + VERTEX.x * 0.5) * hit_intensity
    );

    // 2. Break effect
    if (break_progress > 0.0) {
        // Move vertices outward from the center
        vec2 center = vec2(0.0, 0.0);
        vec2 dir = normalize(pos - center + 0.001); // avoid zero length
        pos += dir * break_progress * 20.0;

        // Optional: slight rotation for visual chaos
        float angle = break_progress * 3.14 * 0.25; // max 45 degrees
        float cos_t = cos(angle);
        float sin_t = sin(angle);
        vec2 rotated;
        rotated.x = (pos.x - center.x) * cos_t - (pos.y - center.y) * sin_t;
        rotated.y = (pos.x - center.x) * sin_t + (pos.y - center.y) * cos_t;
        pos = center + rotated;
    }

    VERTEX.xy = pos;
}
