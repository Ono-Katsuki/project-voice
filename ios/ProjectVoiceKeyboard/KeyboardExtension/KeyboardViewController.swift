//
//  KeyboardViewController.swift
//  KeyboardExtension
//
//  Created for Project Voice
//  Copyright 2025 Google LLC
//

import UIKit

class KeyboardViewController: UIInputViewController {

    private var keyboardView: KeyboardView!
    private var apiClient: ApiClient!
    private var debounceTimer: Timer?
    private var lastFetchedText: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()

        NSLog("========================================")
        NSLog("[KeyboardVC] viewDidLoad called!")
        NSLog("[KeyboardVC] API Endpoint: %@", UserSettings.shared.apiEndpoint)
        NSLog("========================================")

        // Initialize API client
        apiClient = ApiClient()

        // Setup keyboard view
        setupKeyboardView()

        // Update emotion labels for current language
        keyboardView.updateEmotionLabels()

        // Show initial phrases on load
        showInitialPhrases()
    }

    private func setupKeyboardView() {
        keyboardView = KeyboardView(frame: .zero)
        keyboardView.delegate = self
        keyboardView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(keyboardView)

        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyboardView.heightAnchor.constraint(equalToConstant: 520) // Larger height for iPad
        ])
    }

    override func textWillChange(_ textInput: UITextInput?) {
        // Called when the text context is about to change
    }

    override func textDidChange(_ textInput: UITextInput?) {
        // Called after the text context has changed
        let proxy = textDocumentProxy

        // Cancel previous debounce timer
        debounceTimer?.invalidate()

        // Get current text for suggestions
        if let contextBefore = proxy.documentContextBeforeInput, !contextBefore.isEmpty {
            // Skip if text hasn't changed (e.g., keyboard switch)
            if contextBefore == lastFetchedText {
                print("[KeyboardVC] textDidChange: text unchanged, skipping fetch")
                return
            }

            print("[KeyboardVC] textDidChange: '\(contextBefore)'")

            // Debounce: wait 50ms before fetching to avoid duplicate calls
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                self?.fetchSuggestionsIfNeeded(for: contextBefore)
            }
        } else {
            print("[KeyboardVC] textDidChange: text is empty, showing initial phrases")
            lastFetchedText = ""
            // Show initial phrases when text is empty
            showInitialPhrases()
        }
    }

    private func showInitialPhrases() {
        let settings = UserSettings.shared
        let currentLanguage = settings.currentLanguage
        let initialPhrases = settings.getInitialPhrases(for: currentLanguage)

        DispatchQueue.main.async { [weak self] in
            self?.keyboardView.showInitialPhrases(initialPhrases)
        }
    }

    private func fetchSuggestionsIfNeeded(for text: String) {
        // Skip if already fetched for this text
        if text == lastFetchedText {
            print("[KeyboardVC] Already fetched for this text, skipping")
            return
        }

        lastFetchedText = text
        fetchSuggestions(for: text)
    }

    private func fetchSuggestions(for text: String) {
        print("[KeyboardVC] fetchSuggestions called for: '\(text.prefix(30))...'")

        // Get current emotion from keyboard view
        let emotion = keyboardView.getCurrentEmotion()

        // Get history-based suggestions
        let settings = UserSettings.shared
        let language = LanguageManager.shared.getLanguage(code: settings.currentLanguage)
        let historySuggestions = HistoryProcessor.searchSuggestionsFromHistory(
            text: text,
            history: settings.messageHistoryWithPrefix,
            language: language ?? JapaneseLanguage()
        )

        print("[KeyboardVC] History suggestions: \(historySuggestions.count)")

        // Fetch AI suggestions
        print("[KeyboardVC] Calling apiClient.fetchSuggestions...")
        apiClient.fetchSuggestions(for: text, emotion: emotion) { [weak self] response in
            print("[KeyboardVC] API response received: \(response != nil)")
            guard let self = self, let response = response else {
                // If API fails, show history suggestions only
                DispatchQueue.main.async { [weak self] in
                    self?.keyboardView.updateSuggestions(historySuggestions, currentText: text)
                }
                return
            }

            DispatchQueue.main.async { [weak self] in
                let settings = UserSettings.shared
                let isV11 = settings.aiConfig == "voice_v11" || settings.aiConfig == "voice_v11_simple"

                var processedSentences: [String]

                if isV11 {
                    // For v11: response is slash-separated tokens (e.g., "し/た/から/精度/高い")
                    // Don't prepend context - it's handled during confirmation
                    // Just use the response directly for block display
                    processedSentences = response.sentences
                } else {
                    // For standard models: use ignoreUnnecessaryDiffs
                    let (firstHalf, secondHalf) = TextProcessor.splitLastFewSentencesForLLM(text)
                    processedSentences = response.sentences.map { sentence in
                        firstHalf + DiffProcessor.ignoreUnnecessaryDiffs(original: secondHalf, modified: sentence)
                    }
                }

                if isV11 {
                    // For v11: show only 3 AI predictions (no history, no words)
                    let suggestions = Array(processedSentences.prefix(3))
                    self?.keyboardView.updateSuggestions(sentences: suggestions, words: [], currentText: text)
                } else {
                    // For standard models: combine history + AI sentences
                    var allSentences = historySuggestions + processedSentences

                    // Remove duplicates from sentences
                    var seen = Set<String>()
                    allSentences = allSentences.filter { suggestion in
                        let lowercased = suggestion.lowercased()
                        if seen.contains(lowercased) {
                            return false
                        }
                        seen.insert(lowercased)
                        return true
                    }

                    // Remove duplicates from words
                    var seenWords = Set<String>()
                    let uniqueWords = response.words.filter { word in
                        let lowercased = word.lowercased()
                        if seenWords.contains(lowercased) {
                            return false
                        }
                        seenWords.insert(lowercased)
                        return true
                    }

                    // Update UI with separated sentences and words
                    self?.keyboardView.updateSuggestions(sentences: allSentences, words: uniqueWords, currentText: text)
                }
            }
        }
    }
}

// MARK: - KeyboardViewDelegate
extension KeyboardViewController: KeyboardViewDelegate {

    func keyboardView(_ view: KeyboardView, didTapKey key: String) {
        let proxy = textDocumentProxy

        switch key {
        case "delete":
            proxy.deleteBackward()
        case "space":
            proxy.insertText(" ")
        case "return":
            proxy.insertText("\n")
        case "shift":
            // Toggle shift state
            keyboardView.toggleShift()
            return  // Don't fetch suggestions for shift
        case "123":
            // Switch to number keyboard
            keyboardView.switchToNumberMode()
            return  // Don't fetch suggestions for mode switch
        case "ABC":
            // Switch to alphabet keyboard
            keyboardView.switchToAlphabetMode()
            return  // Don't fetch suggestions for mode switch
        case "小":
            // Small kana conversion (Japanese)
            handleSmallKanaConversion()
        default:
            proxy.insertText(key)
        }

        // Manually trigger fetch after key press
        // Note: textDidChange will also be called by iOS, but may be delayed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self = self else { return }
            if let contextBefore = self.textDocumentProxy.documentContextBeforeInput, !contextBefore.isEmpty {
                self.fetchSuggestionsIfNeeded(for: contextBefore)
            }
        }
    }

    func keyboardView(_ view: KeyboardView, didSelectSuggestion suggestion: String) {
        let proxy = textDocumentProxy
        let settings = UserSettings.shared

        // Clear suggestions immediately while loading
        keyboardView.clearSuggestions()

        // Get current text before modification
        let currentText = proxy.documentContextBeforeInput ?? ""

        // Check if using v11 tuned model (including simple mode)
        let isV11 = settings.aiConfig == "voice_v11" || settings.aiConfig == "voice_v11_simple"

        if isV11 {
            // For v11: delete the prefix (trailing hiragana/alphabet) that was used for prediction
            let (_, textForLLM) = TextProcessor.splitLastFewSentencesForLLM(currentText)
            let (_, v11Prefix) = TextProcessor.splitForV11(textForLLM)

            // Delete the prefix characters
            for _ in 0..<v11Prefix.count {
                proxy.deleteBackward()
            }
        } else {
            // For standard models: delete the current word being typed
            if let currentWord = getCurrentWord() {
                for _ in 0..<currentWord.count {
                    proxy.deleteBackward()
                }
            }
        }

        // Normalize suggestion and insert
        let normalizedSuggestion = TextProcessor.normalize(suggestion, isLastInputFromSuggestion: true)
        proxy.insertText(normalizedSuggestion)

        // Update message history with prefix tracking
        let prefix = TextProcessor.getUserInputPrefix(normalizedSuggestion)
        settings.addToMessageHistory(text: normalizedSuggestion, prefix: prefix)

        // Update conversation history
        settings.lastInputSpeech = normalizedSuggestion
        settings.addToConversationHistory(message: ConversationMessage(role: "user", content: normalizedSuggestion))

        // Fetch next suggestions based on updated text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            if let newText = self.textDocumentProxy.documentContextBeforeInput, !newText.isEmpty {
                self.lastFetchedText = ""  // Force new fetch
                self.fetchSuggestions(for: newText)
            }
        }
    }

    func keyboardViewDidRequestKeyboardChange(_ view: KeyboardView) {
        advanceToNextInputMode()
    }

    private func getCurrentWord() -> String? {
        let proxy = textDocumentProxy
        guard let contextBefore = proxy.documentContextBeforeInput else {
            return nil
        }

        let components = contextBefore.components(separatedBy: .whitespacesAndNewlines)
        return components.last
    }

    private func handleSmallKanaConversion() {
        let proxy = textDocumentProxy

        // Get current text
        guard let currentText = proxy.documentContextBeforeInput, !currentText.isEmpty else {
            return
        }

        // Cycle through: normal → dakuten → handakuten → small → normal
        if let converted = JapaneseKanaProcessor.cycleKanaConversion(currentText) {
            // Delete last character and insert converted version
            proxy.deleteBackward()
            let newLastChar = String(converted.suffix(1))
            proxy.insertText(newLastChar)
        }
    }
}
