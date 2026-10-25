//! halo-splash: draw a PNG on the framebuffer.
//!
//! Stands in for the shell until the Flutter embedder exists (ROADMAP
//! Phase 1). The pixel work is plain functions so it is tested off-device;
//! the framebuffer itself is in [`fb`] (Linux only).

use std::io::Cursor;
use thiserror::Error;

#[cfg(target_os = "linux")]
pub mod fb;

/// Ground color (`carbon`, #0C0C0B) used around an image that does not fill
/// the screen. B, G, R, X byte order.
pub const GROUND: [u8; 4] = [0x0B, 0x0C, 0x0C, 0xFF];

#[derive(Debug, Error)]
pub enum ImageError {
    #[error("PNG decode failed: {0}")]
    Decode(#[from] png::DecodingError),
    #[error("unsupported PNG format: {0:?} {1:?}")]
    Unsupported(png::ColorType, png::BitDepth),
}

/// A decoded image: RGBA, 8 bits per channel, row-major.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rgba {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
}

/// Decode a PNG into RGBA8. Accepts 8-bit RGB and RGBA.
pub fn decode_png(bytes: &[u8]) -> Result<Rgba, ImageError> {
    let mut decoder = png::Decoder::new(Cursor::new(bytes));
    decoder.set_transformations(png::Transformations::EXPAND);
    let mut reader = decoder.read_info()?;
    let mut buf = vec![0; reader.output_buffer_size().unwrap_or(0)];
    let info = reader.next_frame(&mut buf)?;
    let data = &buf[..info.buffer_size()];
    let pixels = match (info.color_type, info.bit_depth) {
        (png::ColorType::Rgba, png::BitDepth::Eight) => data.to_vec(),
        (png::ColorType::Rgb, png::BitDepth::Eight) => data
            .as_chunks::<3>()
            .0
            .iter()
            .flat_map(|p| [p[0], p[1], p[2], 0xFF])
            .collect(),
        (c, d) => return Err(ImageError::Unsupported(c, d)),
    };
    Ok(Rgba {
        width: info.width,
        height: info.height,
        pixels,
    })
}

/// Geometry of a 32-bit framebuffer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Surface {
    pub width: u32,
    pub height: u32,
    /// Bytes per row, which can exceed `width * 4`.
    pub stride: u32,
}

/// Draw `img` centered on `dst` (B, G, R, X bytes), filling the rest with
/// [`GROUND`]. An image larger than the surface is cropped, not scaled.
/// Transparent pixels are composited over the ground.
pub fn blit_centered(img: &Rgba, dst: &mut [u8], surface: Surface) {
    let Surface {
        width: dw,
        height: dh,
        stride,
    } = surface;
    let stride = stride as usize;
    // Offsets of the image on the surface; negative when cropping.
    let ox = (dw as i64 - img.width as i64) / 2;
    let oy = (dh as i64 - img.height as i64) / 2;

    for y in 0..dh as usize {
        let row_start = y * stride;
        let Some(row) = dst.get_mut(row_start..row_start + dw as usize * 4) else {
            break;
        };
        for (x, px) in row.as_chunks_mut::<4>().0.iter_mut().enumerate() {
            let sx = x as i64 - ox;
            let sy = y as i64 - oy;
            let inside = sx >= 0 && sy >= 0 && sx < img.width as i64 && sy < img.height as i64;
            if !inside {
                *px = GROUND;
                continue;
            }
            let i = (sy as usize * img.width as usize + sx as usize) * 4;
            let (r, g, b, a) = (
                img.pixels[i],
                img.pixels[i + 1],
                img.pixels[i + 2],
                img.pixels[i + 3],
            );
            px[0] = over(b, GROUND[0], a);
            px[1] = over(g, GROUND[1], a);
            px[2] = over(r, GROUND[2], a);
            px[3] = 0xFF;
        }
    }
}

/// `src` over `bg` with alpha `a` (0 to 255).
fn over(src: u8, bg: u8, a: u8) -> u8 {
    let a = a as u32;
    ((src as u32 * a + bg as u32 * (255 - a) + 127) / 255) as u8
}

#[cfg(test)]
mod tests {
    use super::*;

    fn img(w: u32, h: u32, rgba: [u8; 4]) -> Rgba {
        Rgba {
            width: w,
            height: h,
            pixels: rgba.repeat((w * h) as usize),
        }
    }

    fn px(buf: &[u8], x: usize, y: usize, stride: usize) -> [u8; 4] {
        let i = y * stride + x * 4;
        [buf[i], buf[i + 1], buf[i + 2], buf[i + 3]]
    }

    #[test]
    fn an_exact_fit_copies_the_image_as_bgrx() {
        let s = Surface {
            width: 2,
            height: 2,
            stride: 8,
        };
        let mut dst = vec![0u8; 16];
        blit_centered(&img(2, 2, [10, 20, 30, 255]), &mut dst, s);
        for y in 0..2 {
            for x in 0..2 {
                assert_eq!(px(&dst, x, y, 8), [30, 20, 10, 255]);
            }
        }
    }

    #[test]
    fn a_smaller_image_is_centered_on_the_ground() {
        let s = Surface {
            width: 4,
            height: 4,
            stride: 16,
        };
        let mut dst = vec![0u8; 64];
        blit_centered(&img(2, 2, [255, 0, 0, 255]), &mut dst, s);
        assert_eq!(px(&dst, 0, 0, 16), GROUND);
        assert_eq!(px(&dst, 3, 3, 16), GROUND);
        assert_eq!(px(&dst, 1, 1, 16), [0, 0, 255, 255]);
        assert_eq!(px(&dst, 2, 2, 16), [0, 0, 255, 255]);
        assert_eq!(px(&dst, 0, 1, 16), GROUND);
        assert_eq!(px(&dst, 3, 2, 16), GROUND);
    }

    #[test]
    fn a_larger_image_is_cropped_around_its_center() {
        let s = Surface {
            width: 2,
            height: 2,
            stride: 8,
        };
        let mut big = img(4, 4, [0, 0, 0, 255]);
        // Mark the center 2 x 2 white.
        for y in 1..3 {
            for x in 1..3 {
                let i = (y * 4 + x) * 4;
                big.pixels[i..i + 4].copy_from_slice(&[255, 255, 255, 255]);
            }
        }
        let mut dst = vec![0u8; 16];
        blit_centered(&big, &mut dst, s);
        for y in 0..2 {
            for x in 0..2 {
                assert_eq!(px(&dst, x, y, 8), [255, 255, 255, 255]);
            }
        }
    }

    #[test]
    fn stride_padding_is_left_alone() {
        let s = Surface {
            width: 1,
            height: 2,
            stride: 8,
        };
        let mut dst = vec![7u8; 16];
        blit_centered(&img(1, 2, [1, 2, 3, 255]), &mut dst, s);
        assert_eq!(&dst[4..8], &[7, 7, 7, 7]);
        assert_eq!(&dst[12..16], &[7, 7, 7, 7]);
    }

    #[test]
    fn transparency_shows_the_ground() {
        let s = Surface {
            width: 1,
            height: 1,
            stride: 4,
        };
        let mut dst = vec![0u8; 4];
        blit_centered(&img(1, 1, [255, 255, 255, 0]), &mut dst, s);
        assert_eq!(&dst[..3], &GROUND[..3]);
        blit_centered(&img(1, 1, [255, 255, 255, 255]), &mut dst, s);
        assert_eq!(&dst[..3], &[255, 255, 255]);
    }

    #[test]
    fn a_short_buffer_does_not_panic() {
        let s = Surface {
            width: 4,
            height: 4,
            stride: 16,
        };
        let mut dst = vec![0u8; 20];
        blit_centered(&img(2, 2, [1, 2, 3, 255]), &mut dst, s);
    }

    fn encode(w: u32, h: u32, color: png::ColorType, data: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        {
            let mut enc = png::Encoder::new(&mut out, w, h);
            enc.set_color(color);
            enc.set_depth(png::BitDepth::Eight);
            let mut w = enc.write_header().unwrap_or_else(|e| panic!("{e}"));
            w.write_image_data(data).unwrap_or_else(|e| panic!("{e}"));
        }
        out
    }

    #[test]
    fn decodes_rgba_png() {
        let bytes = encode(1, 1, png::ColorType::Rgba, &[1, 2, 3, 4]);
        let i = decode_png(&bytes).unwrap_or_else(|e| panic!("{e}"));
        assert_eq!((i.width, i.height), (1, 1));
        assert_eq!(i.pixels, [1, 2, 3, 4]);
    }

    #[test]
    fn decodes_rgb_png_as_opaque() {
        let bytes = encode(2, 1, png::ColorType::Rgb, &[1, 2, 3, 4, 5, 6]);
        let i = decode_png(&bytes).unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(i.pixels, [1, 2, 3, 255, 4, 5, 6, 255]);
    }

    #[test]
    fn garbage_is_an_error_not_a_panic() {
        assert!(decode_png(b"not a png").is_err());
    }
}
