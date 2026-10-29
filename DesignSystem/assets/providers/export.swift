import AppKit
import Foundation

let root=URL(fileURLWithPath:CommandLine.arguments[1])
let source=URL(fileURLWithPath:#filePath).deletingLastPathComponent()
let target=root.appendingPathComponent("ProviderMarks.xcassets")
try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true)
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}".utf8).write(to:target.appendingPathComponent("Contents.json"))
for name in ["provider-ant-ling","provider-cerebras-rings","provider-cerebras-center","provider-together","provider-fireworks","provider-radius"] {
    let isAnt=name=="provider-ant-ling"
    let image=NSImage(contentsOf:source.appendingPathComponent(name+(isAnt ? ".ico" : ".svg")))!
    let side=isAnt ? 256 : 512
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:side,pixelsHigh:side,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    bitmap.size=NSSize(width:side,height:side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    NSColor.clear.setFill()
    NSRect(x:0,y:0,width:side,height:side).fill(using:.copy)
    image.draw(in:NSRect(x:0,y:0,width:side,height:side),from:.zero,operation:.sourceOver,fraction:1)
    NSGraphicsContext.restoreGraphicsState()
    let set=target.appendingPathComponent(name+".imageset")
    try FileManager.default.createDirectory(at:set,withIntermediateDirectories:true)
    try bitmap.representation(using:.png,properties:[:])!.write(to:set.appendingPathComponent(name+".png"))
    let info: [String:Any] = ["images":[["filename":name+".png","idiom":"universal"]],"info":["author":"xcode","version":1]]
    try JSONSerialization.data(withJSONObject:info,options:[.prettyPrinted,.sortedKeys]).write(to:set.appendingPathComponent("Contents.json"))
    print("Exported \(name) \(side)×\(side)")
}
