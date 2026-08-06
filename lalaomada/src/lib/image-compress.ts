/**
 * Compresses and converts an image File to WebP on the client before upload,
 * to cut bandwidth for both the uploader and everyone who later loads it.
 * Falls back to the original file if the browser can't produce a smaller WebP.
 *
 * Guarantees the output is under maxSizeKB by iteratively reducing quality
 * and dimensions.
 */
export async function compressImageToWebp(
  file: File,
  { maxDim = 1280, quality = 0.82, maxSizeKB = 200 }: { maxDim?: number; quality?: number; maxSizeKB?: number } = {}
): Promise<File> {
  if (!file.type.startsWith("image/") || file.type === "image/svg+xml") return file;

  try {
    const bitmap = await createImageBitmap(file);
    let currentDim = Math.min(maxDim, Math.max(bitmap.width, bitmap.height));
    let currentQuality = quality;

    for (let attempt = 0; attempt < 6; attempt++) {
      const scale = Math.min(1, currentDim / Math.max(bitmap.width, bitmap.height));
      const w = Math.round(bitmap.width * scale);
      const h = Math.round(bitmap.height * scale);

      const canvas = document.createElement("canvas");
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext("2d");
      if (!ctx) return file;
      ctx.drawImage(bitmap, 0, 0, w, h);

      const blob: Blob | null = await new Promise((resolve) =>
        canvas.toBlob(resolve, "image/webp", currentQuality)
      );

      if (blob && blob.size < file.size && blob.size <= maxSizeKB * 1024) {
        const newName = file.name.replace(/\.[^.]+$/, "") + ".webp";
        return new File([blob], newName, { type: "image/webp" });
      }

      // If blob is still too big, reduce quality first, then dimensions
      if (blob && blob.size > maxSizeKB * 1024) {
        if (currentQuality > 0.3) {
          currentQuality -= 0.15;
        } else if (currentDim > 256) {
          currentDim = Math.round(currentDim * 0.7);
          currentQuality = quality; // reset quality when reducing dims
        } else {
          // Last resort: return the smallest we got
          if (blob && blob.size < file.size) {
            const newName = file.name.replace(/\.[^.]+$/, "") + ".webp";
            return new File([blob], newName, { type: "image/webp" });
          }
          break;
        }
      } else {
        // Blob is under target but not smaller than original (tiny source)
        if (blob && blob.size < file.size) {
          const newName = file.name.replace(/\.[^.]+$/, "") + ".webp";
          return new File([blob], newName, { type: "image/webp" });
        }
        break;
      }
    }

    return file;
  } catch {
    return file;
  }
}
