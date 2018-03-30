//
//  xliff.swift
//  Localize
//
//  Created by Artem Shimanski on 28.03.2018.
//  Copyright © 2018 Artem Shimanski. All rights reserved.
//

import Foundation

enum XLIFFError: Error {
	case attributeNotFound(String)
	case elementNotFound(String)
}

extension XMLElement {
	func attribute(forName name: String) throws -> String {
		guard let value = attribute(forName: name)?.stringValue else {throw XLIFFError.attributeNotFound(name)}
		return value
	}
	
	func attribute(forName name: String) -> String? {
		return attribute(forName: name)?.stringValue
	}

	func element(forName name: String) throws -> String {
		guard let value = elements(forName: name).first?.stringValue else {throw XLIFFError.elementNotFound(name)}
		return value
	}
	
	func element(forName name: String) -> String? {
		return self.elements(forName: name).first?.stringValue
	}

}

class XLIFF {
	class File {
		class TransUnit {
			let id: String
			let source: String
			var target: String?
			var note: String?
			let element: XMLElement
			
			init (_ element: XMLElement) throws {
				self.element = element
				id = try element.attribute(forName: "id")
				source = try element.element(forName: "source")
				target = element.element(forName: "target")
				note = element.element(forName: "note")
			}
		}
		
		let original: String
		let sourceLanguage: String
		let targetLanguage: String?
		let translations: [TransUnit]?
		let element: XMLElement
		
		init (_ element: XMLElement) throws {
			self.element = element
			original = try element.attribute(forName: "original")
			sourceLanguage = try element.attribute(forName: "source-language")
			targetLanguage = element.attribute(forName: "target-language")
			translations = try element.elements(forName: "body").first?.elements(forName: "trans-unit").map {try TransUnit($0)}
		}
		
	}
	let files: [File]
	let document: XMLDocument
	let url: URL
	
	init (contentsOf url: URL) throws {
		document = try XMLDocument(contentsOf: url, options: [])
		self.url = url
		files = try document.rootElement()?.elements(forName: "file").map { return try File($0)} ?? []
	}
}
