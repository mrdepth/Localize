//
//  main.swift
//  Localize
//
//  Created by Artem Shimanski on 28.03.2018.
//  Copyright © 2018 Artem Shimanski. All rights reserved.
//

import Foundation
// Usage:
// Localize -spreadsheet <spreadsheetID> [-languages "<ISO_CODES>"]-clientID <google_client_id> -clientSecret <google_client_secret> [-info <Info.plist>]

// Turn on the Google Sheets API
// Google Sheets guide: https://developers.google.com/sheets/api/quickstart/ios
// Google APIsConsle: https://console.developers.google.com/apis/credentials

let projectPath: String! = ProcessInfo.processInfo.environment["PROJECT_FILE_PATH"]
let projectDir: String! = ProcessInfo.processInfo.environment["PROJECT_DIR"]
let tempDir: String! = ProcessInfo.processInfo.environment["TEMP_DIR"]

guard projectPath != nil && projectDir != nil && tempDir != nil else {
	print("error: run in projects target")
	exit(EXIT_FAILURE)
}

let commandLineArguments = CommandLine.commandLineArguments
let spreadsheetID: String! = commandLineArguments["-spreadsheet"]

let clientID: String! = commandLineArguments["-clientID"]
let clientSecret: String! = commandLineArguments["-clientSecret"]

guard spreadsheetID != nil else {
	print("error: missing spreadsheet argument")
	exit(EXIT_FAILURE)
}

guard clientID != nil && clientSecret != nil else {
	print("error: missing clientID or clientSecret")
	exit(EXIT_FAILURE)
}

let keychain = commandLineArguments["-password-keychain"] ?? "com.shimanski.localize.\(spreadsheetID!)"

let languages = commandLineArguments["-languages"]?.split(separator: " ").map({String($0)}) ?? FileManager.default.enumerator(at: URL(fileURLWithPath: projectDir), includingPropertiesForKeys: [.isDirectoryKey])?.map{$0 as! URL}
	.filter { url -> Bool in
		guard try! url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {return false}
		return url.pathExtension == "lproj" && url.lastPathComponent != "Base.lproj"
	}
	.map { url in url.deletingPathExtension().lastPathComponent }

var currentVersion: String?

if let infoPath = commandLineArguments["-info"] {
	do {
		let info = (try PropertyListSerialization.propertyList(from: Data(contentsOf: URL.init(fileURLWithPath: infoPath)), options: [], format: nil)) as? [String: Any]
		currentVersion = info?["CFBundleVersion"] as? String
	}
	catch {
		print("error: unable to find Info.plist at \"\(infoPath)\"")
		exit(EXIT_FAILURE)
	}
}

func authorize() -> Future<GTMAppAuthFetcherAuthorization> {
	let promise = Promise<GTMAppAuthFetcherAuthorization>()
	if let authorization = GTMAppAuthFetcherAuthorization(fromKeychainForName: keychain) {
		try! promise.fulfill(authorization)
	}
	else {
		var handler: OIDRedirectHTTPHandler! = OIDRedirectHTTPHandler(successURL: URL(string: "http://openid.github.io/AppAuth-iOS/redirect/"))
		let localRedirectURI = handler.startHTTPListener(nil)
		let configuration = GTMAppAuthFetcherAuthorization.configurationForGoogle()
		
		let scopes = [kGTLRAuthScopeSheetsDrive]
		let request = OIDAuthorizationRequest(configuration: configuration, clientId: clientID, clientSecret: clientSecret, scopes: scopes, redirectURL: localRedirectURI, responseType: OIDResponseTypeCode, additionalParameters: nil)
		handler.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, callback: { (state, error) in
			if let authState = state {
				let gtmAuthorization = GTMAppAuthFetcherAuthorization(authState: authState)
				GTMAppAuthFetcherAuthorization.save(gtmAuthorization, toKeychainForName: keychain)
				try! promise.fulfill(gtmAuthorization)
			}
			else {
				try! promise.fail(error!)
			}
		})
		
		promise.future.finally {
			handler = nil
		}
	}
	return promise.future
}

enum Header: String {
	case version
	case note
	case file
	case id
	case source
}

let kUnused = "<Unused>"
let predefinedHeaders = [Header.version.rawValue, Header.note.rawValue, Header.file.rawValue, Header.id.rawValue, Header.source.rawValue]

enum LocalizeError: Error {
	case invalidSpreadsheetsContent
	case invalidServerResponse
	case sourceStringMismatch
}

func loadXLIFFs() -> Future<[XLIFF]> {
	return DispatchQueue.global(qos: .utility).async {
		
		return try languages?.map { language -> XLIFF in
			shell("xcodebuild", "-exportLocalizations", "-localizationPath", tempDir, "-project", projectPath, "-exportLanguage", language)
			let url = URL(fileURLWithPath: tempDir).appendingPathComponent("\(language).xcloc/Localized Contents/\(language).xliff")
			return try XLIFF(contentsOf: url)
		} ?? []
	}
}

func loadSpreadsheet(service: GTLRSheetsService) -> Future<GTLRSheets_ValueRange> {
	var service: GTLRSheetsService! = service
	
	let promise = Promise<GTLRSheets_ValueRange>()
	let query = GTLRSheetsQuery_SpreadsheetsValuesGet.query(withSpreadsheetId: spreadsheetID, range: "A1:Z1000")
	service.executeQuery(query) { (_, result, error) in
		do {
			guard let result = result as? GTLRSheets_ValueRange,
				let range = result.range?.components(separatedBy: "!").last,
				result.majorDimension == kGTLRSheetsMajorDimensionRows,
				range.components(separatedBy: ":").first == "A1"
				else {throw error ?? LocalizeError.invalidSpreadsheetsContent}
			if let firstRow = result.values?.first {
				guard let headers = firstRow as? [String],
					Set(headers).isSuperset(of: Set(predefinedHeaders))
					else {throw error ?? LocalizeError.invalidSpreadsheetsContent}
			}
			
			try promise.fulfill(result)
		}
		catch {
			try! promise.fail(error)
		}
		service = nil
	}
	return promise.future
}

func translations(from xliffs: [XLIFF]) -> Set<String> {
	return Set(xliffs.compactMap{$0.files.first?.targetLanguage})
}

func translations(from: GTLRSheets_ValueRange) -> Set<String>? {
	guard let headers = from.values?.first as? [String] else {return nil}
	return Set(headers).subtracting(Set(predefinedHeaders))
}

var isFinished = false
authorize().then(on: .global(qos: .utility)) { auth in
	let service = GTLRSheetsService()
	service.authorizer = auth

	let xliffs = try loadXLIFFs().get()
	let spreadsheet = try loadSpreadsheet(service: service).get()
	let localTranslations = translations(from: xliffs)
	let remoteTranslations = translations(from: spreadsheet)
	
	var modifiedLanguages = Set<String>()
	var unusedUnits = Set<Int>()
	var usedUnits = Set<Int>()
	var hasErrors = false
	let spreadsheetValues = (spreadsheet.values as? [[String]])?[1...].map{$0}
	
	if let headers = spreadsheet.values?.first as? [String], let remoteTranslations = remoteTranslations?.intersection(localTranslations) {
		spreadsheetValues?.enumerated().forEach { (index, row) in
			let file = row.column(name: Header.file.rawValue, headers: headers)
			let id = row.column(name: Header.id.rawValue, headers: headers)
			let source = row.column(name: Header.source.rawValue, headers: headers)
			let note = row.column(name: Header.note.rawValue, headers: headers)
			
			let translations = remoteTranslations.reduce(into: [:]) { (result, language) in result[language] = row.column(name: language, headers: headers) }
			guard !translations.isEmpty else {return}

			var isUnused = true

			if let file = file, let id = id {
				do {
					try translations.forEach { (language, target) in
						guard let transUnit = xliffs.transUnit(file: file, id: id, language: language)
							else {return}
						guard transUnit.source == source else {
							print("error: source string mismatch (row: \(index + 2), id: '\(transUnit.id)', source: '\(source ?? "")', expected: '\(transUnit.source)')")
							hasErrors = true
							throw LocalizeError.sourceStringMismatch
						}
						if transUnit.updateIfNeeded(target: target, note: note) {
							modifiedLanguages.insert(language)
							usedUnits.insert(index)
						}
						isUnused = false
					}
				}
				catch {
					
				}
			}
			/*else if let source = source {
				translations.forEach { (language, target) in
					let transUnits = xliffs.transUnits(source: source, language: language)
					guard !transUnits.isEmpty else {return}
					transUnits.forEach { transUnit in
						if transUnit.updateIfNeeded(target: target, note: note) {
							modifiedLanguages.insert(language)
						}
					}
					isUnused = false
				}
			}*/
			if isUnused {
				unusedUnits.insert(index)
			}
		}
	}
	
	guard !hasErrors else {exit(EXIT_FAILURE)}
	let missingTranslations = localTranslations.subtracting(remoteTranslations ?? []).sorted()

	var update = [GTLRSheets_ValueRange]()
	let headers = (spreadsheet.values?.first as? [String])?.appending(missingTranslations) ?? predefinedHeaders.appending(localTranslations.sorted())
	var xliffsValues = xliffs.spreadsheetValues(headers: headers)
	
	if let currentVersion = currentVersion, let column = headers.index(of: Header.version.rawValue) {
		for i in xliffsValues.indices {
			xliffsValues[i][column] = currentVersion
		}
	}
	
	if spreadsheet.values?.isEmpty != false { //Initial
		let range = GTLRSheets_ValueRange()
		range.majorDimension = kGTLRSheetsMajorDimensionRows
		range.range = "A1:\(Address(row: xliffsValues.count + 1, column:headers.count - 1))"
		range.values = [headers.map{$0}].appending(xliffsValues)
		update.append(range)
	}
	else {
		if !missingTranslations.isEmpty {
			let range = GTLRSheets_ValueRange()
			range.majorDimension = kGTLRSheetsMajorDimensionRows
			range.range = "\(Address(row: 0, column: headers.count - missingTranslations.count)):\(Address(row: spreadsheetValues?.count ?? 0, column:headers.count - 1))"
			var values = [missingTranslations]
			
			values.append(contentsOf:
				spreadsheetValues?.map { row -> [String] in
					guard let file = row.column(name: Header.file.rawValue, headers: headers),
						let id = row.column(name: Header.id.rawValue, headers: headers) else {return []}
					return xliffsValues.first { i in
						return i.column(name: Header.file.rawValue, headers: headers) == file &&
								i.column(name: Header.id.rawValue, headers: headers) == id
						}?[headers.count-missingTranslations.count..<headers.count].map{$0} ?? []
				} ?? []
			)
			range.values = values
			update.append(range)
		}
		let missingValues = xliffsValues.filter { local in
			guard let file = local.column(name: Header.file.rawValue, headers: headers),
				let id = local.column(name: Header.id.rawValue, headers: headers) else {return false}
			return spreadsheetValues?.contains(where: { remote in
				return remote.column(name: Header.file.rawValue, headers: headers) == file &&
					remote.column(name: Header.id.rawValue, headers: headers) == id
			}) != true
		}
		if !missingValues.isEmpty {
			let range = GTLRSheets_ValueRange()
			range.majorDimension = kGTLRSheetsMajorDimensionRows
			let from = Address(row: (spreadsheetValues?.count ?? 0) + 1, column: 0)
			let to = Address(row: from.row + missingValues.count - 1, column: headers.count - 1)
			range.range = "\(from):\(to)"
			range.values = missingValues
			update.append(range)
		}
	}
	
	if let column = headers.index(of: Header.note.rawValue) {
		update.append(contentsOf:
			unusedUnits.compactMap { i -> GTLRSheets_ValueRange? in
				guard spreadsheetValues?[i].column(name: Header.note.rawValue, headers: headers) != kUnused else {return nil}
				let range = GTLRSheets_ValueRange()
				range.majorDimension = kGTLRSheetsMajorDimensionRows
				range.range = "\(Address(row: i + 1, column: column))"
				range.values = [[kUnused]]
				return range
			}
		)
	}
	if let currentVersion = currentVersion, let column = headers.index(of: Header.version.rawValue) {
		update.append(contentsOf:
			usedUnits.compactMap { i -> GTLRSheets_ValueRange? in
				guard spreadsheetValues?[i].column(name: Header.version.rawValue, headers: headers) != currentVersion else {return nil}
				let range = GTLRSheets_ValueRange()
				range.majorDimension = kGTLRSheetsMajorDimensionRows
				range.range = "\(Address(row: i + 1, column: column))"
				range.values = [[currentVersion]]
				return range
			}
		)
	}
	
	if !update.isEmpty {
		let request = GTLRSheets_BatchUpdateValuesRequest()
		request.valueInputOption = kGTLRSheetsValueInputOptionRaw
		request.data = update
		
		let query = GTLRSheetsQuery_SpreadsheetsValuesBatchUpdate.query(withObject: request, spreadsheetId: spreadsheetID)
		let promise = Promise<GTLRSheets_BatchUpdateValuesResponse>()
		service.executeQuery(query, completionHandler: { (_, result, error) in
			if let result = result as? GTLRSheets_BatchUpdateValuesResponse {
				try! promise.fulfill(result)
			}
			else {
				try! promise.fail(error ?? LocalizeError.invalidServerResponse)
			}
			
		})
		promise.future.wait()
	}
	
	let regex = try! NSRegularExpression(pattern: "<trans-unit id=\"(.*?)\">", options: [NSRegularExpression.Options.dotMatchesLineSeparators])
	
	let cmd = try modifiedLanguages.compactMap { language in
		xliffs.first {$0.files.first?.targetLanguage == language}
	}.map { xliff in

		let s = NSMutableString(string: xliff.document.xmlString)
		for mach in regex.matches(in: s as String, options: [], range: NSMakeRange(0, s.length)).reversed() {
			let r = mach.range(at: 1)
			let id = s.substring(with: r).replacingOccurrences(of: "\n", with: "&#10;")
			s.replaceCharacters(in: r, with: id)
		}
		
		let data = (s as String).data(using: .utf8)!
		try data.write(to: xliff.url)
		
		return "xcodebuild -importLocalizations -localizationPath \"\(xliff.url.deletingLastPathComponent().deletingLastPathComponent().path)\" -project \"\(projectPath!)\""
	}.joined(separator: " && ")
	
	if !cmd.isEmpty {
		shell("bash", "-c", "\(cmd) &")
	}
}.catch(on: .main) { error in
	print("error: \(error)")
}.finally(on: .main) {
	isFinished = true
}

while !isFinished && RunLoop.current.run(mode: .defaultRunLoopMode, before: .distantFuture) {
}



