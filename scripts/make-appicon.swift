#!/usr/bin/env swift
//
// Draws assets/AppIcon-1024.png: a thermometer over a teal→indigo gradient,
// with tick marks reading like a scale. Run once; the PNG is committed, so a
// build never depends on this script.
//
//   swift scripts/make-appicon.swift assets/AppIcon-1024.png
//
import AppKit
import CoreGraphics
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/AppIcon-1024.png"
let size = 1024

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("could not create the drawing context") }

let s = CGFloat(size)

// Rounded-square background, the macOS app-icon shape.
let inset = s * 0.08
let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
let squircle = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.13, green: 0.72, blue: 0.71, alpha: 1),  // teal
        CGColor(red: 0.20, green: 0.36, blue: 0.80, alpha: 1),  // indigo
    ] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
ctx.restoreGState()

// Thermometer: a capsule stem with a bulb, drawn as one filled path.
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let cx = s * 0.40
let bulbR = s * 0.115
let bulbY = s * 0.30
let stemW = s * 0.115
let stemTop = s * 0.76

ctx.setFillColor(white)
ctx.fillEllipse(in: CGRect(x: cx - bulbR, y: bulbY - bulbR, width: bulbR * 2, height: bulbR * 2))
ctx.addPath(CGPath(roundedRect: CGRect(x: cx - stemW / 2, y: bulbY, width: stemW, height: stemTop - bulbY),
                   cornerWidth: stemW / 2, cornerHeight: stemW / 2, transform: nil))
ctx.fillPath()

// The mercury column, tinted so the bulb reads as "warm".
let warm = CGColor(red: 1.0, green: 0.45, blue: 0.35, alpha: 1)
let innerR = bulbR * 0.62
let innerW = stemW * 0.44
ctx.setFillColor(warm)
ctx.fillEllipse(in: CGRect(x: cx - innerR, y: bulbY - innerR, width: innerR * 2, height: innerR * 2))
ctx.addPath(CGPath(roundedRect: CGRect(x: cx - innerW / 2, y: bulbY, width: innerW, height: s * 0.30),
                   cornerWidth: innerW / 2, cornerHeight: innerW / 2, transform: nil))
ctx.fillPath()

// Scale ticks to the right — long, short, long — so the icon reads as a
// measuring instrument rather than a generic thermometer glyph.
ctx.setStrokeColor(white)
ctx.setLineCap(.round)
let tickX = cx + stemW * 0.95
for (i, y) in stride(from: s * 0.44, through: s * 0.72, by: s * 0.07).enumerated() {
    let long = i % 2 == 0
    ctx.setLineWidth(s * (long ? 0.030 : 0.024))
    ctx.move(to: CGPoint(x: tickX, y: y))
    ctx.addLine(to: CGPoint(x: tickX + s * (long ? 0.16 : 0.10), y: y))
    ctx.strokePath()
}

guard let image = ctx.makeImage() else { fatalError("could not render the image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }

let url = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: url)
print("wrote \(outPath) (\(size)x\(size))")
