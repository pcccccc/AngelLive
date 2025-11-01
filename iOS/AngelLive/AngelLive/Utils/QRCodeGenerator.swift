//
//  QRCodeGenerator.swift
//  AngelLive
//
//  Created by Claude on 11/1/25.
//

import UIKit
import CoreImage.CIFilterBuiltins

class QRCodeGenerator {

    /// 生成二维码图片
    /// - Parameter string: 要编码的字符串
    /// - Returns: 二维码 UIImage
    static func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        let transform = CGAffineTransform(scaleX: 10, y: 10)

        if let outputImage = filter.outputImage?.transformed(by: transform) {
            if let cgimg = context.createCGImage(outputImage, from: outputImage.extent) {
                return UIImage(cgImage: cgimg)
            }
        }

        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
}
