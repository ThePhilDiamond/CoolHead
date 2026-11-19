import AppKit
import SwiftUI

// Cool Head's social card for GitHub (Settings, General, Social preview): 1280 x 640, everything that matters inside
// the 80-pixel border GitHub's template asks for, so nothing is cropped. Draws from the README's logo and panel
// screenshot (made-up samples), so redraw it when they change:
//
//     swift scripts/social-card.swift
//
// It writes docs/images/social-card.png. Chosen by Phil, 19 November 2026: "The Split social card is great", with "a
// few bonus tools to check related symptoms like the network hardware cleaner etc."
let logo = NSImage(contentsOfFile: "docs/images/logo.png")!
let panel = NSImage(contentsOfFile: "docs/images/panel-light.png")!

let navy = Color(red: 0.12, green: 0.23, blue: 0.35)
let sky = Color(red: 0.42, green: 0.74, blue: 0.95)
let deep = Color(red: 0.18, green: 0.53, blue: 0.84)
let ice = Color(red: 0.93, green: 0.97, blue: 1.0)

struct Chip: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 20, weight: .semibold)).foregroundStyle(navy)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.9)))
            .overlay(Capsule().strokeBorder(deep.opacity(0.25), lineWidth: 1))
    }
}

struct Split: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [ice, Color(red: 0.80, green: 0.91, blue: 0.99)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .center, spacing: 44) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 22) {
                        Image(nsImage: logo).resizable().frame(width: 108, height: 108)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cool Head").font(.system(size: 62, weight: .bold)).foregroundStyle(navy)
                            Text("Let cooler heads prevail.").font(.system(size: 26, weight: .medium).italic()).foregroundStyle(deep)
                        }
                    }
                    Text("Why is your Mac running hot or slow? Cool\u{00A0}Head says why in one sentence, with options to act\u{00A0}in\u{00A0}one\u{00A0}click.")
                        .font(.system(size: 27, weight: .regular)).foregroundStyle(navy)
                        .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 26)
                    Text("Plus tools to test your network, check your battery and hardware, and clear space.")
                        .font(.system(size: 22, weight: .medium)).foregroundStyle(deep)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                    HStack(spacing: 10) {
                        Chip(text: "Free and open source")
                        Chip(text: "macOS menu bar")
                    }
                    .padding(.top, 22)
                    HStack(spacing: 10) {
                        Chip(text: "Apple Silicon and Intel")
                        Chip(text: "No account, no analytics")
                    }
                    .padding(.top, 10)
                }
                .frame(width: 600, alignment: .leading)
                Image(nsImage: panel).resizable().aspectRatio(contentMode: .fit)
                    .frame(height: 470)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                    .shadow(color: navy.opacity(0.25), radius: 24, y: 10)
            }
            .frame(width: 1120, height: 480)
            .offset(x: 80, y: 80)
        }
        .frame(width: 1280, height: 640)
    }
}

@MainActor func save<V: View>(_ view: V, _ path: String) {
    let r = ImageRenderer(content: view.environment(\.colorScheme, .light))
    r.scale = 1
    guard let cg = r.cgImage else { print("no image"); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print(path, cg.width, cg.height)
}

MainActor.assumeIsolated { save(Split(), "docs/images/social-card.png") }
