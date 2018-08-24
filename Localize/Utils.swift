//
//  Utils.swift
//  localize
//
//  Created by Artem Shimanski on 30.03.2018.
//  Copyright © 2018 Artem Shimanski. All rights reserved.
//

import Foundation

@discardableResult
func shell(_ args: String...) -> Int32 {
	let task = Process()
	task.launchPath = "/usr/bin/env"
	task.arguments = args
	task.launch()
	task.waitUntilExit()
	return task.terminationStatus
}

extension CommandLine {
	static var commandLineArguments: [String: String] {
		var args = [String: String]()
		var key: String? = nil
		self.arguments[1...].forEach { i in
			if i.hasPrefix("-") {
				key = i
			}
			else if let k = key {
				args[k] = i
				key = nil
			}
		}
		return args
	}
}

struct Address: ExpressibleByStringLiteral, CustomStringConvertible {
	static func <(lhs: Address, rhs: Address) -> Bool {
		return lhs.row < rhs.row || (lhs.row == rhs.row && lhs.column < rhs.column)
	}
	
	static func ==(lhs: Address, rhs: Address) -> Bool {
		return lhs.row == rhs.row && lhs.column == rhs.column
	}
	
	var row: Int
	var column: Int
	
	init(row: Int, column: Int) {
		self.row = row
		self.column = column
	}
	
	init(stringLiteral value: String) {
		if value.count < 2 {
			row = 0
			column = 0
		}
		else {
			column = Int(value.first!.unicodeScalars.first!.value - "A".unicodeScalars.first!.value)
			let s = value[value.index(after: value.startIndex)...]
			row = (Int(s) ?? 1) - 1
		}
		
	}
	
	var description: String {
		return "\(Unicode.Scalar("A".unicodeScalars.first!.value + UInt32(column))!)\(row + 1)"
	}
}
extension Array where Element == String {
	func column(name: String, headers: [String]) -> String? {
		guard let i = headers.index(of: name), count > i else {return nil}
		return self[i]
	}
}

extension Array where Element == XLIFF {
	func transUnit(file: String, id: String, language: String) -> XLIFF.File.TransUnit? {
		return self.lazy.map{$0.files}.joined().first {$0.original == file && $0.targetLanguage == language}?.translations?.first {$0.id == id}
	}
	
	func transUnits(source: String, language: String) -> [XLIFF.File.TransUnit] {
		let tr = map{$0.files}.joined().filter {$0.targetLanguage == language}.compactMap {$0.translations?.filter {$0.source == source}}
		return tr.joined().map{$0}
	}

	func spreadsheetValues(headers: [String]) -> [[String]] {
		
		var localRows: [String: [String: [String: String]]] = [:]
		
		forEach { xliff in
			xliff.files.filter {$0.targetLanguage != nil}
				.forEach { file in
					file.translations?.forEach { i in
						localRows[file.original, default: [:]][i.id, default: [Header.file.rawValue: file.original, Header.id.rawValue: i.id, Header.source.rawValue: i.source, Header.note.rawValue: i.note ?? ""]][file.targetLanguage!] = i.target ?? ""
					}
			}
		}
		
		return localRows.values.map{$0.map{(key, row) in (key, headers.map{row[$0] ?? ""})}}.joined().sorted{$0.0 < $1.0}.map{$0.1}
	}
}

extension XLIFF.File.TransUnit {
	func updateIfNeeded(target: String, note: String?) -> Bool {
		guard self.target != target || self.note != note else {return false}
		(element.elements(forName: "target").first ?? {
			let node = XMLElement(name: "target")
			element.addChild(node)
			return node
		}()).stringValue = target
		self.target = target

		if let note = note {
			(element.elements(forName: "note").first ?? {
				let node = XMLElement(name: "note")
				element.addChild(node)
				return node
				}()).stringValue = note
			self.note = note
		}
		return true
	}
}


extension Array {
	func appending(_ other: Array) -> Array {
		var new = self
		new.append(contentsOf: other)
		return new
	}
}

