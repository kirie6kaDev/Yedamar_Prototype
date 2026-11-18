# Quaternius assets integrated in V5

Downloaded from the creator's official itch.io free download flow on 18 November 2026. Only the free **Standard** archives were obtained. Each archive includes a CC0 1.0 Public Domain Dedication; the original license texts are preserved beside this file. No extracted or recreated assets from Genshin Impact or The Sims are included.

| Official pack | Integration | License |
|---|---|---|
| [Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html) · [official download](https://quaternius.itch.io/universal-base-characters) | Male/female face and eyes, derived head geometry, four hairstyles | CC0; `Quaternius_universal-base-characters.txt` |
| [Modular Character Outfits — Fantasy](https://quaternius.com/packs/modularcharacteroutfitsfantasy.html) · [official download](https://quaternius.itch.io/modular-character-outfits-fantasy) | Male/female Peasant and Ranger clothing | CC0; `Quaternius_modular-character-outfits-fantasy.txt` |
| [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) · [official download](https://quaternius.itch.io/universal-animation-library) | Standard animation file; retargeted movement, interaction, combat, seated and work aliases | CC0; `Quaternius_universal-animation-library.txt` |
| [Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html) · [official download](https://quaternius.itch.io/stylized-nature-megakit) | Textured broadleaf/conifer trees, bushes, fern, grass, flowers, rocks | CC0; `Quaternius_stylized-nature-megakit.txt` |

The project integration clips the base body to a head, preserves skinning, attaches hair, and combines it with a fully clothed outfit. Runtime bone animation is retargeted to that outfit's rest pose. Tool attachment sockets are added for the existing gameplay tools. Original source textures are retained; Godot import settings use mipmaps, desktop VRAM compression and a 1024 pixel maximum size.

Nature replacements are uniformly normalized to the previous model height and base position. Existing coordinates, interaction IDs, heightfield and navigation obstacle radii are retained. Shader code in `assets/visuals` is original project code: soft foliage lighting/wind and procedural roof tiles. It is not the author's paid Source shader.

Author: **Quaternius**, https://quaternius.com/ . Attribution is voluntarily retained even though CC0 does not require it.
