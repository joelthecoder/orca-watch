# Orca Watch identity

The surface signal mark combines a swept orca dorsal silhouette with an open observation ring and a short wake. The ring means watching; the wake means recent activity. This is an original mark, independent from Orca's official identity.

The alternatives were a literal observation eye and an OW monogram. The eye was generic; the monogram lost the product's orca subject. The surface signal keeps a distinctive animal contour while working within a circular observer shape.

The editable masters are `app-icon.svg` and `logo-mark.svg`. The app icon uses an ocean tile; the logo has a transparent canvas. Keep the ring, fin and wake proportions together. Do not substitute a stock whale glyph. The logo's pale silhouette belongs on dark surfaces. For a monochrome mark, use one foreground color and preserve the eye patch as a background-colored cutout.

Palette: ocean highlight `#183F4E`, ocean depth `#071722`, observation mint `#59D8C6`, silhouette `#F4FAF8`, eye patch `#0B202B`. Mint is an accent rather than small body text on a light background. UI typography uses the platform system face; no font files or custom wordmark are distributed.

`make icons` exports the canonical app icon at 16, 32, 64, 128, 256, 512 and 1024 pixels, packages a complete legacy macOS ICNS, and emits the 256-pixel Orca project PNG plus its 1024-pixel master. Shipping assets live in this directory and `Orca/ProjectIcon`; inspection exports live under `.build-app/previews`. The legacy ICNS path supports macOS 14 without requiring Icon Composer. No layered Icon Composer appearance previews are claimed.

The 16-pixel mark prioritizes the white fin and mint ring. The eye patch and wake are secondary at that scale. Keep clear space of at least one ring stroke around the standalone mark. Avoid putting text inside the app icon.
