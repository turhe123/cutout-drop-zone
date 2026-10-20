# CutoutDropZone — specification

**Tagline:** Drop a photo and get back a transparent-background cutout of its subject in seconds, fully offline.

**Category:** Files & Conversion

**Inspired by (paid):** Droply ($9 one-time)

**Frameworks:** SwiftUI, AppKit, Vision, CoreImage, ImageIO, UniformTypeIdentifiers

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Droply is a native macOS background removal tool that works offline and is sold as a one-time perpetual license for about 9 dollars, letting you drag processed images straight to Finder, browsers or other apps. Offline background removal is a recurring request because web tools upload your photos and charge per image, and several App Store clones appear with subscriptions, showing steady demand for a simple private option. Apple's Vision framework now ships the needed subject lifting model, so the app can be tiny.

Feature set for CutoutDropZone: a small window app with a large drop zone. Drop one or many images (PNG, JPEG, HEIC, TIFF) and each is processed with subject lifting. Results appear in a grid with a checkerboard background. Per-image controls: toggle between original and cutout, choose a replacement background (transparent, white, black, or a color), add an optional soft edge feather of 0 to 5 pixels, and trim to the subject bounds. Export as PNG with transparency, or JPEG with the chosen background color. Cutouts can be dragged out of the app to Finder or any other app, copied to the clipboard, or saved all at once to a folder with a suffix such as -cutout.

UI spec: a single window with a toolbar containing Add Files, Export All, Copy, and a background color picker. Left is the drop zone and a list of thumbnails, right is a preview with a before and after toggle that also works with the space bar. Empty state shows a dashed rounded rectangle and the words Drop images here. The Settings pane holds default export format, output folder, feather amount, default background, and a trim to bounds toggle. No menu bar item is needed but a Dock icon drop target should also accept images.

Technical approach: load with ImageIO into a CGImage, then run VNGenerateForegroundInstanceMaskRequest through a VNImageRequestHandler. Call generateScaledMaskForImage for all instances, which returns a CVPixelBuffer mask, convert to a CIImage, and apply CIBlendWithMask to composite the original over a clear or colored background. Feathering uses CIGaussianBlur on the mask with a clamp. Cropping uses the bounding box found from the mask. Writing uses CGImageDestination. Dragging out uses NSItemProvider with a temporary file URL in the caches folder. Drops are accepted with onDrop for file URLs and public image types. Processing runs on a background task with progress per image. Requires macOS 14, where the foreground mask request is available, and no permissions are needed beyond the user-chosen output folder.

Edge cases and error handling: if no subject is found, mark the item with a warning badge and keep the original. Multiple subjects can be selected by clicking the preview to include or exclude each instance, using the instance index map. Very large images are downscaled for the model and the mask is scaled back up. Preserve EXIF orientation. Never overwrite originals, and add a counter if the output name already exists. Handle unsupported or corrupted files with a short error row and continue the batch.
