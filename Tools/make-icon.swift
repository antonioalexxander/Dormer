#!/usr/bin/env swift
// Renders Dormer's app icon (1024×1024 PNG) with Core Graphics.
// Usage: swift Tools/make-icon.swift <output.png>
//
// Motif: a dormer (a window that projects from a roof) with a warm, lit window
// against a dusk sky. Original artwork, no third-party assets.

import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"

guard
    let context = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("Cannot create context") }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linearGradient(_ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
}

// Canvas uses a bottom-left origin. macOS icon grid: 824×824 body centered, ~185 pt corner radius.
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the squircle.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
context.addPath(bodyPath)
context.setFillColor(color(0x1B2A6B))
context.fillPath()
context.restoreGState()

// Sky.
context.saveGState()
context.addPath(bodyPath)
context.clip()
linearGradient([color(0x1E2A78), color(0x4B3FA8), color(0xE0816B)], from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.minY))

// A few stars.
for (x, y, r) in [(250.0, 800.0, 7.0), (340.0, 730.0, 4.5), (770.0, 820.0, 6.0), (700.0, 760.0, 3.5), (820.0, 690.0, 4.0)] {
    context.setFillColor(color(0xFFFFFF, 0.85))
    context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// Main roof slope (dark slate), sweeping across the bottom.
let roof = CGMutablePath()
roof.move(to: CGPoint(x: body.minX - 20, y: 470))
roof.addLine(to: CGPoint(x: body.maxX + 20, y: 300))
roof.addLine(to: CGPoint(x: body.maxX + 20, y: body.minY - 20))
roof.addLine(to: CGPoint(x: body.minX - 20, y: body.minY - 20))
roof.closeSubpath()
context.addPath(roof)
context.setFillColor(color(0x23243F))
context.fillPath()

// Roof shingle lines.
context.setStrokeColor(color(0xFFFFFF, 0.06))
context.setLineWidth(6)
for offset in stride(from: 0.0, through: 300.0, by: 60.0) {
    context.move(to: CGPoint(x: body.minX - 20, y: 470 - offset - 40))
    context.addLine(to: CGPoint(x: body.maxX + 20, y: 300 - offset - 40))
}
context.strokePath()

// Dormer: walls + gable roof, centered.
let cx: CGFloat = 512
let wallWidth: CGFloat = 330
let wallBottom: CGFloat = 330
let wallTop: CGFloat = 560
let walls = CGRect(x: cx - wallWidth / 2, y: wallBottom, width: wallWidth, height: wallTop - wallBottom)
context.setFillColor(color(0xF2EBDD))
context.fill(walls)

let gable = CGMutablePath()
gable.move(to: CGPoint(x: walls.minX - 46, y: wallTop - 10))
gable.addLine(to: CGPoint(x: cx, y: wallTop + 190))
gable.addLine(to: CGPoint(x: walls.maxX + 46, y: wallTop - 10))
gable.addLine(to: CGPoint(x: walls.maxX + 20, y: wallTop - 34))
gable.addLine(to: CGPoint(x: cx, y: wallTop + 140))
gable.addLine(to: CGPoint(x: walls.minX - 20, y: wallTop - 34))
gable.closeSubpath()
context.addPath(gable)
context.setFillColor(color(0x3A3B63))
context.fillPath()

// Gable infill.
let infill = CGMutablePath()
infill.move(to: CGPoint(x: walls.minX - 20, y: wallTop - 34))
infill.addLine(to: CGPoint(x: cx, y: wallTop + 140))
infill.addLine(to: CGPoint(x: walls.maxX + 20, y: wallTop - 34))
infill.closeSubpath()
context.addPath(infill)
context.setFillColor(color(0xF2EBDD))
context.fillPath()

// Warm glow behind the window.
let windowRect = CGRect(x: cx - 95, y: wallBottom + 40, width: 190, height: 230)
context.saveGState()
context.setShadow(offset: .zero, blur: 70, color: color(0xFFC861, 0.9))
context.setFillColor(color(0xFFD27A))
context.fill(windowRect)
context.restoreGState()

// Lit window panes.
context.saveGState()
context.addRect(windowRect)
context.clip()
linearGradient([color(0xFFE6A3), color(0xFFB347)], from: CGPoint(x: 0, y: windowRect.maxY), to: CGPoint(x: 0, y: windowRect.minY))
context.restoreGState()

// Window frame and mullions.
context.setStrokeColor(color(0x3A3B63))
context.setLineWidth(18)
context.stroke(windowRect)
context.setLineWidth(12)
context.move(to: CGPoint(x: windowRect.midX, y: windowRect.minY))
context.addLine(to: CGPoint(x: windowRect.midX, y: windowRect.maxY))
context.move(to: CGPoint(x: windowRect.minX, y: windowRect.midY))
context.addLine(to: CGPoint(x: windowRect.maxX, y: windowRect.midY))
context.strokePath()

// Sill.
context.setFillColor(color(0x3A3B63))
context.fill(CGRect(x: windowRect.minX - 22, y: windowRect.minY - 26, width: windowRect.width + 44, height: 20))

context.restoreGState()

// Subtle top highlight on the squircle edge.
context.saveGState()
context.addPath(bodyPath)
context.setStrokeColor(color(0xFFFFFF, 0.18))
context.setLineWidth(3)
context.strokePath()
context.restoreGState()

guard let image = context.makeImage() else { fatalError("Cannot render") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
