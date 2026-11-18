# Campus lighting

LabVolt uses Godot 4.5's Forward+ renderer on desktop and Mobile renderer on mobile. The existing CampusLightingRig owns the procedural sky, sun, ambient fill, and filmic environment. Its day/night curve preserves usable indoor ambient light independently of the outdoor sun. The Graphics & Display brightness control changes tonemap exposure.

Room builders use real broad spotlights at the existing fixtures. The workshop and corridor also use short-range, shadowless ceiling spill. M104 uses warmer pendant and wall lighting. Shadows come from fixed, authored fixtures and the outdoor sun. M101 keeps its three fixtures at Medium and above, and the specified teaching rooms keep one each. Off disables shadow maps and the workshop and cafeteria's instanced furniture contact shading.

The workshop, M104, and corridors use a satin tile shader. Its local specular response uses the scene's actual lights and is controlled by Reflections. That setting also controls environmental reflections and reflection probes. Compatibility uses the same materials and its own supported bloom implementation. On desktop, Ultra enables screen-space reflections and ambient occlusion. The preset uses 2x MSAA. Shadows on local spotlights fade between 12 and 18 metres, while direct light and specular highlights remain visible up to 40 metres.

Room-local nodes follow the existing presentation streamer. A six-meter margin keeps an active room from toggling immediately at the distance threshold. Hall lights have gradual distance fade. The graphics controller registers arriving presentation nodes and reapplies settings using their authored values.

Graphics & Display saves presets and individual choices in user://campus_graphics.cfg. The page exposes brightness, indoor fixture intensity, lighting tone, shadow and bloom quality, reflections, render scale, MSAA, filtering, and view distance alongside the existing display and world controls. Medium is the default. Existing shadow and bloom toggles migrate to their quality equivalents.

Renderer reference: https://docs.godotengine.org/en/4.5/tutorials/rendering/renderers.html

Ultra adds area reflections for the corridor, M104 and M106 tiled floors. The shader projects the viewing ray through the reflected fixture plane and softens each panel or pendant footprint. The existing positional lights still supply direct illumination. Lighting tone, fixture intensity and Reflections control the additional sheen. The corridor adds selected wall washes at the highest fixture tier.
