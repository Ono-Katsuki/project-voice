//
//  KeyboardView.swift
//  KeyboardExtension
//
//  Created for Project Voice
//  Copyright 2025 Google LLC
//

import UIKit

protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, didTapKey key: String)
    func keyboardView(_ view: KeyboardView, didSelectSuggestion suggestion: String)
    func keyboardViewDidRequestKeyboardChange(_ view: KeyboardView)
}

class KeyboardView: UIView {

    weak var delegate: KeyboardViewDelegate?

    private var mode: KeyboardMode = .alphabet
    private var isShifted: Bool = false

    private let emotionSelector = EmotionSelector()
    private let suggestionBar = SuggestionBar()
    private let keyboardStackView = UIStackView()

    // Delete long press support
    private var deleteTimer: Timer?
    private var isDeleteLongPressing = false

    // English alphabet keyboard (QWERTY - iOS standard)
    private let alphabetKeys = [
        ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"],
        ["k", "l", "m", "n", "o", "p", "q", "r", "s", "t"],
        ["u", "v", "w", "x", "y", "z", "(", ")", "[", "]"],
        ["-", "_", "/", ":", ";", "&", "@", "#", "*", "'"]
    ]

    // Japanese hiragana keyboard (iOS standard flick layout style)
    // All rows have exactly 10 keys for perfect grid alignment
    private let hiraganaKeys = [
        ["わ", "ら", "や", "ま", "は", "な", "た", "さ", "か", "あ"],
        ["を", "り", "", "み", "ひ", "に", "ち", "し", "き", "い"],
        ["ん", "る", "ゆ", "む", "ふ", "ぬ", "つ", "す", "く", "う"],
        ["ー", "れ", "", "め", "へ", "ね", "て", "せ", "け", "え"],
        ["゛゜小", "ろ", "よ", "も", "ほ", "の", "と", "そ", "こ", "お"]
    ]

    private let numberKeys = [
        ["年", "月", "日", "時", "分", "1", "2", "3"],
        ["×", "÷", "+", "-", "=", "4", "5", "6"],
        ["♪", "☆", "%", "¥", "〒", "7", "8", "9"],
        ["→", "~", "・", "…", "○", "'", "0", "・"]
    ]

    private let symbolKeys = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
        ["123", ".", ",", "?", "!", "'", "delete"]
    ]

    enum KeyboardMode {
        case alphabet
        case hiragana
        case number
        case symbol
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Set initial mode based on language
        let currentLanguage = UserSettings.shared.currentLanguage
        mode = (currentLanguage == "ja-JP") ? .hiragana : .alphabet
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // Adaptive keyboard background (light/dark mode)
        if #available(iOS 13.0, *) {
            backgroundColor = UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0) // Dark mode
                default:
                    return UIColor(red: 0.82, green: 0.835, blue: 0.863, alpha: 1.0) // Light mode
                }
            }
        } else {
            backgroundColor = UIColor(red: 0.82, green: 0.835, blue: 0.863, alpha: 1.0)
        }

        // Setup emotion selector
        emotionSelector.delegate = self
        emotionSelector.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emotionSelector)

        // Setup suggestion bar
        suggestionBar.delegate = self
        suggestionBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(suggestionBar)

        // Setup keyboard stack view
        keyboardStackView.axis = .vertical
        keyboardStackView.spacing = 8
        keyboardStackView.distribution = .fillEqually
        keyboardStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyboardStackView)

        // Hide emotion selector - now using button in keyboard
        emotionSelector.isHidden = true

        NSLayoutConstraint.activate([
            emotionSelector.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            emotionSelector.leadingAnchor.constraint(equalTo: leadingAnchor),
            emotionSelector.trailingAnchor.constraint(equalTo: trailingAnchor),
            emotionSelector.heightAnchor.constraint(equalToConstant: 0), // Set to 0

            suggestionBar.topAnchor.constraint(equalTo: topAnchor, constant: 4), // Start from top
            suggestionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            suggestionBar.heightAnchor.constraint(equalToConstant: 110), // 3 rows with larger text

            keyboardStackView.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor, constant: 8),
            keyboardStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            keyboardStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            keyboardStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        renderKeyboard()
    }

    private func renderKeyboard() {
        // Clear existing keys
        keyboardStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let keys = getCurrentKeys()

        // Fixed left column buttons: mode switches, model switch, and keyboard switch (bottom)
        let leftColumnKeys = ["☆123", "ABC", "あいう", getModelButtonLabel(), "🌐"]

        // Fixed right column buttons: delete, space, return
        let rightColumnKeys = ["delete", "空白", "改行"]

        // Render each row with left and right fixed buttons
        for (index, row) in keys.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 4
            rowStack.distribution = .fill

            // Left side: fixed button (mode switch or keyboard switch)
            if index < leftColumnKeys.count {
                let leftButton = createKeyButton(for: leftColumnKeys[index])
                leftButton.widthAnchor.constraint(equalToConstant: 80).isActive = true
                rowStack.addArrangedSubview(leftButton)
            } else {
                // For rows beyond the fixed buttons, add empty spacer
                let spacer = UIView()
                spacer.widthAnchor.constraint(equalToConstant: 80).isActive = true
                rowStack.addArrangedSubview(spacer)
            }

            // Middle: main keys with equal distribution
            let mainKeysStack = UIStackView()
            mainKeysStack.axis = .horizontal
            mainKeysStack.spacing = 4
            mainKeysStack.distribution = .fillEqually

            for key in row {
                if key.isEmpty {
                    // Empty key: add invisible spacer
                    let spacer = UIView()
                    spacer.backgroundColor = .clear
                    mainKeysStack.addArrangedSubview(spacer)
                } else {
                    let button = createKeyButton(for: key)
                    mainKeysStack.addArrangedSubview(button)
                }
            }

            rowStack.addArrangedSubview(mainKeysStack)

            // Right side: fixed button (delete, space, return, or emotion selector)
            if index < rightColumnKeys.count {
                let rightButton = createKeyButton(for: rightColumnKeys[index])
                rightButton.widthAnchor.constraint(equalToConstant: 90).isActive = true
                rowStack.addArrangedSubview(rightButton)
            } else if index == keys.count - 1 {
                // Last row: add emotion selector button
                let emotionButton = createEmotionSelectorButton()
                emotionButton.widthAnchor.constraint(equalToConstant: 90).isActive = true
                rowStack.addArrangedSubview(emotionButton)
            } else {
                // For other rows, add empty spacer
                let spacer = UIView()
                spacer.widthAnchor.constraint(equalToConstant: 90).isActive = true
                rowStack.addArrangedSubview(spacer)
            }

            keyboardStackView.addArrangedSubview(rowStack)
        }
    }

    private func createBottomRow() -> UIStackView {
        let rowStack = UIStackView()
        rowStack.axis = .horizontal
        rowStack.spacing = 4
        rowStack.distribution = .fill

        // ☆123 button
        let modeButton = createKeyButton(for: "☆123")
        modeButton.widthAnchor.constraint(equalToConstant: 60).isActive = true

        // ABC button
        let abcButton = createKeyButton(for: "ABC")
        abcButton.widthAnchor.constraint(equalToConstant: 55).isActive = true

        // Spacer 1
        let spacer1 = UIView()
        spacer1.widthAnchor.constraint(equalToConstant: 10).isActive = true

        // Spacer 2
        let spacer2 = UIView()
        spacer2.widthAnchor.constraint(equalToConstant: 10).isActive = true

        // Spacer 3 (flexible - takes remaining space)
        let spacer3 = UIView()

        // あいう button
        let hiraganaButton = createKeyButton(for: "あいう")
        hiraganaButton.widthAnchor.constraint(equalToConstant: 55).isActive = true

        // 🌐 button
        let globeButton = createKeyButton(for: "🌐")
        globeButton.widthAnchor.constraint(equalToConstant: 45).isActive = true

        // ⌨︎ button
        let keyboardButton = createKeyButton(for: "⌨︎")
        keyboardButton.widthAnchor.constraint(equalToConstant: 45).isActive = true

        rowStack.addArrangedSubview(modeButton)
        rowStack.addArrangedSubview(abcButton)
        rowStack.addArrangedSubview(spacer1)
        rowStack.addArrangedSubview(spacer2)
        rowStack.addArrangedSubview(spacer3)
        rowStack.addArrangedSubview(hiraganaButton)
        rowStack.addArrangedSubview(globeButton)
        rowStack.addArrangedSubview(keyboardButton)

        return rowStack
    }

    private func createKeyButton(for key: String) -> UIButton {
        let button = UIButton(type: .system)
        let displayText = (mode == .alphabet && isShifted) ? key.uppercased() : key

        button.setTitle(displayText, for: .normal)

        // Store the original key value in accessibilityIdentifier
        button.accessibilityIdentifier = key

        // iOS standard key styling (adaptive for light/dark mode)
        if #available(iOS 13.0, *) {
            button.backgroundColor = UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(red: 0.35, green: 0.35, blue: 0.37, alpha: 1.0) // Dark mode key
                default:
                    return .white // Light mode key
                }
            }
            button.setTitleColor(UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return .white // Dark mode text
                default:
                    return .black // Light mode text
                }
            }, for: .normal)
        } else {
            button.backgroundColor = .white
            button.setTitleColor(.black, for: .normal)
        }
        button.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .regular)
        button.layer.cornerRadius = 5

        // iOS standard shadow
        button.layer.shadowColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.3).cgColor
        button.layer.shadowOpacity = 1.0
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 0

        // Special styling for special keys (iOS standard gray keys)
        if ["shift", "delete", "⌫", "123", "☆123", "ABC", "#", "#+=", "🌐", "小", "゛゜小", "あいう", "空白", "改行"].contains(key) {
            if #available(iOS 13.0, *) {
                button.backgroundColor = UIColor { traitCollection in
                    switch traitCollection.userInterfaceStyle {
                    case .dark:
                        return UIColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0) // Dark mode special key
                    default:
                        return UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1.0) // Light mode special key
                    }
                }
            } else {
                button.backgroundColor = UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1.0)
            }

            // Special symbols for shift and delete
            if key == "shift" {
                button.setTitle("⇧", for: .normal)
                button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
            } else if key == "delete" || key == "⌫" {
                button.setTitle("⌫", for: .normal)
                button.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .light)
            } else {
                button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .regular)
            }
        }

        button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)

        // Add long press support for delete key
        if key == "delete" || key == "⌫" {
            button.addTarget(self, action: #selector(deleteTouchDown(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(deleteTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }

        return button
    }

    @objc private func deleteTouchDown(_ sender: UIButton) {
        // Start delete timer for long press
        isDeleteLongPressing = false
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.isDeleteLongPressing = true
            self?.startContinuousDelete()
        }
    }

    @objc private func deleteTouchUp(_ sender: UIButton) {
        // Stop delete timer
        deleteTimer?.invalidate()
        deleteTimer = nil
        isDeleteLongPressing = false
    }

    private func startContinuousDelete() {
        guard isDeleteLongPressing else { return }

        // Delete one character
        delegate?.keyboardView(self, didTapKey: "delete")

        // Schedule next delete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.startContinuousDelete()
        }
    }

    private func createEmotionSelectorButton() -> UIButton {
        let button = UIButton(type: .system)

        // Get current emotion and display its emoji
        let currentEmotion = emotionSelector.getCurrentEmotion()
        let emoji = getEmotionEmoji(for: currentEmotion)

        button.setTitle(emoji, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .regular)

        // Gray background like other special keys
        button.backgroundColor = UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1.0)
        button.setTitleColor(.black, for: .normal)
        button.layer.cornerRadius = 5

        // iOS standard shadow
        button.layer.shadowColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.3).cgColor
        button.layer.shadowOpacity = 1.0
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 0

        button.addTarget(self, action: #selector(emotionButtonTapped(_:)), for: .touchUpInside)

        return button
    }

    private func getEmotionEmoji(for emotion: SentenceEmotion) -> String {
        switch emotion {
        case .statement:
            return "💬"  // 普通
        case .question:
            return "❓"  // 質問
        case .request:
            return "🙏"  // お願い
        case .negative:
            return "🚫"  // 否定
        }
    }

    @objc private func emotionButtonTapped(_ sender: UIButton) {
        // Cycle through emotions
        let currentEmotion = emotionSelector.getCurrentEmotion()
        let nextEmotion: SentenceEmotion

        switch currentEmotion {
        case .statement:
            nextEmotion = .question
        case .question:
            nextEmotion = .request
        case .request:
            nextEmotion = .negative
        case .negative:
            nextEmotion = .statement
        }

        // Update emotion selector
        emotionSelector.setEmotion(nextEmotion)

        // Update button emoji
        sender.setTitle(getEmotionEmoji(for: nextEmotion), for: .normal)

        // Re-render keyboard to update the button
        renderKeyboard()
    }

    @objc private func keyTapped(_ sender: UIButton) {
        // Use accessibilityIdentifier to get the original key value
        guard let key = sender.accessibilityIdentifier else { return }

        // Handle special keys
        switch key {
        case "🌐":
            delegate?.keyboardViewDidRequestKeyboardChange(self)
        case let k where k.uppercased() == "SHIFT" || k == "⇧":
            toggleShift()
        case "123", "☆123", "ABC", "#+=", "あいう", "#":
            handleModeSwitch(key)
        case "v11", "v11s", "2.5F", "smart", "fast", "clsc", "AI":
            cycleModel()
        case "空白":
            delegate?.keyboardView(self, didTapKey: "space")
        case "改行":
            delegate?.keyboardView(self, didTapKey: "return")
        case "delete", "⌫":
            delegate?.keyboardView(self, didTapKey: "delete")
        case "小", "゛゜小":
            // Combined key for dakuten, handakuten, and small kana
            delegate?.keyboardView(self, didTapKey: "小")
        default:
            let outputKey = (mode == .alphabet && isShifted) ? key.lowercased() : key
            delegate?.keyboardView(self, didTapKey: outputKey)

            // Auto un-shift after character input
            if isShifted && mode == .alphabet {
                isShifted = false
                renderKeyboard()
            }
        }
    }

    private func handleModeSwitch(_ key: String) {
        switch key {
        case "123", "☆123":
            switchToNumberMode()
        case "ABC":
            // ABC button always switches to alphabet mode
            mode = .alphabet
            renderKeyboard()
        case "あいう":
            // Hiragana button always switches to hiragana mode
            mode = .hiragana
            renderKeyboard()
        case "#", "#+=":
            mode = .symbol
            renderKeyboard()
        default:
            break
        }
    }

    private func getCurrentKeys() -> [[String]] {
        switch mode {
        case .alphabet:
            return alphabetKeys
        case .hiragana:
            return hiraganaKeys
        case .number:
            return numberKeys
        case .symbol:
            return symbolKeys
        }
    }

    private func getModelButtonLabel() -> String {
        let aiConfig = UserSettings.shared.aiConfig
        switch aiConfig {
        case "voice_v11":
            return "v11"
        case "voice_v11_simple":
            return "v11s"
        case "gemini_2_5_flash":
            return "2.5F"
        case "smart":
            return "smart"
        case "fast":
            return "fast"
        case "classic":
            return "clsc"
        default:
            return "AI"
        }
    }

    private func cycleModel() {
        let models = ["smart", "voice_v11", "voice_v11_simple", "gemini_2_5_flash", "fast"]
        let currentModel = UserSettings.shared.aiConfig
        let currentIndex = models.firstIndex(of: currentModel) ?? 0
        let nextIndex = (currentIndex + 1) % models.count
        UserSettings.shared.aiConfig = models[nextIndex]
        NSLog("[KeyboardView] Model switched to: %@", models[nextIndex])
        renderKeyboard()
    }

    private func getModeButtonLabel() -> String {
        switch mode {
        case .alphabet, .hiragana:
            return "123"
        case .number, .symbol:
            let currentLanguage = UserSettings.shared.currentLanguage
            return (currentLanguage == "ja-JP") ? "あいう" : "ABC"
        }
    }

    // MARK: - Public Methods

    func toggleShift() {
        isShifted.toggle()
        renderKeyboard()
    }

    func switchToNumberMode() {
        mode = .number
        renderKeyboard()
    }

    func switchToAlphabetMode() {
        // Choose alphabet or hiragana based on current language
        let currentLanguage = UserSettings.shared.currentLanguage
        mode = (currentLanguage == "ja-JP") ? .hiragana : .alphabet
        renderKeyboard()
    }

    func updateSuggestions(_ suggestions: [String], currentText: String = "") {
        suggestionBar.updateSuggestions(sentences: suggestions, words: [], currentText: currentText)
    }

    func updateSuggestions(sentences: [String], words: [String], currentText: String = "") {
        suggestionBar.updateSuggestions(sentences: sentences, words: words, currentText: currentText)
    }

    func clearSuggestions() {
        suggestionBar.updateSuggestions(sentences: [], words: [], currentText: "")
    }

    func showInitialPhrases(_ phrases: [String]) {
        suggestionBar.showInitialPhrases(phrases)
    }

    func getCurrentEmotion() -> SentenceEmotion {
        return emotionSelector.getCurrentEmotion()
    }

    func getCurrentLanguage() -> String {
        return UserSettings.shared.currentLanguage
    }

    func updateEmotionLabels() {
        emotionSelector.updateLabelsForCurrentLanguage()
    }
}

// MARK: - EmotionSelectorDelegate
extension KeyboardView: EmotionSelectorDelegate {
    func emotionSelector(_ selector: EmotionSelector, didSelectEmotion emotion: SentenceEmotion) {
        // Notify delegate that emotion changed (can trigger new suggestions)
        // For now, just store it - KeyboardViewController will use it on next fetch
    }
}

// MARK: - SuggestionBarDelegate
extension KeyboardView: SuggestionBarDelegate {
    func suggestionBar(_ bar: SuggestionBar, didSelectSuggestion suggestion: String) {
        delegate?.keyboardView(self, didSelectSuggestion: suggestion)
    }
}

// MARK: - SuggestionBar
protocol SuggestionBarDelegate: AnyObject {
    func suggestionBar(_ bar: SuggestionBar, didSelectSuggestion suggestion: String)
    func suggestionBar(_ bar: SuggestionBar, didSelectPartialSuggestion partial: String, from fullSuggestion: String)
}

class SuggestionBar: UIView {

    weak var delegate: SuggestionBarDelegate?

    // 3 rows for sentences
    private let sentenceRow1 = UIScrollView()
    private let sentenceRow2 = UIScrollView()
    private let sentenceRow3 = UIScrollView()

    private let sentenceStack1 = UIStackView()
    private let sentenceStack2 = UIStackView()
    private let sentenceStack3 = UIStackView()

    private var currentText: String = ""
    private var currentLanguage: Language?

    // Block selection overlay
    private var blockSelectionOverlay: UIView?
    private var currentBlockSuggestion: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // Adaptive suggestion bar background (light/dark mode)
        if #available(iOS 13.0, *) {
            backgroundColor = UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0) // Dark mode
                default:
                    return UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0) // Light mode
                }
            }
        } else {
            backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
        }

        // Main vertical stack to hold 3 rows
        let mainStack = UIStackView()
        mainStack.axis = .vertical
        mainStack.spacing = 2
        mainStack.distribution = .fillEqually
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        // Setup each row (3 rows)
        setupRow(scrollView: sentenceRow1, stackView: sentenceStack1)
        setupRow(scrollView: sentenceRow2, stackView: sentenceStack2)
        setupRow(scrollView: sentenceRow3, stackView: sentenceStack3)

        mainStack.addArrangedSubview(sentenceRow1)
        mainStack.addArrangedSubview(sentenceRow2)
        mainStack.addArrangedSubview(sentenceRow3)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupRow(scrollView: UIScrollView, stackView: UIStackView) {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.distribution = .equalSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        // Calculate 1/5 of screen width for left/right margins
        // Approximate screen width for constraint (will be adjusted at runtime)
        let screenWidth = UIScreen.main.bounds.width
        let marginWidth = screenWidth / 5.0

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: marginWidth),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -marginWidth),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }

    func updateSuggestions(sentences: [String], words: [String], currentText: String = "") {
        // Clear existing suggestions
        sentenceStack1.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sentenceStack2.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sentenceStack3.arrangedSubviews.forEach { $0.removeFromSuperview() }

        self.currentText = currentText
        self.currentLanguage = LanguageManager.shared.getLanguage(code: UserSettings.shared.currentLanguage)

        // Add sentences to 3 rows
        let stacks = [sentenceStack1, sentenceStack2, sentenceStack3]
        for (index, sentence) in sentences.prefix(3).enumerated() {
            let container = createSuggestionContainer(for: sentence, isWord: false)
            stacks[index].addArrangedSubview(container)
        }

        // If we have words and less than 3 sentences, use remaining rows for words
        if sentences.count < 3 && !words.isEmpty {
            let startRow = sentences.count
            for (index, word) in words.prefix(3 - startRow).enumerated() {
                let button = createWordButton(word, fullSuggestion: word, rounded: true)
                stacks[startRow + index].addArrangedSubview(button)
            }
        }
    }

    func showInitialPhrases(_ phrases: [String]) {
        // Clear existing suggestions
        sentenceStack1.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sentenceStack2.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sentenceStack3.arrangedSubviews.forEach { $0.removeFromSuperview() }

        self.currentText = ""

        // Distribute phrases across 3 rows horizontally
        let stacks = [sentenceStack1, sentenceStack2, sentenceStack3]
        let phrasesPerRow = (phrases.count + 2) / 3  // Ceiling division

        for (index, phrase) in phrases.enumerated() {
            let rowIndex = index / phrasesPerRow
            if rowIndex < 3 {
                let button = createInitialPhraseButton(phrase)
                stacks[rowIndex].addArrangedSubview(button)
            }
        }
    }

    private func createInitialPhraseButton(_ phrase: String) -> UIButton {
        let button = UIButton(type: .system)

        var config = UIButton.Configuration.filled()
        if #available(iOS 13.0, *) {
            config.baseBackgroundColor = UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0)
                default:
                    return UIColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0)
                }
            }
            config.baseForegroundColor = UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return .white
                default:
                    return .black
                }
            }
        } else {
            config.baseBackgroundColor = UIColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0)
            config.baseForegroundColor = .black
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        config.cornerStyle = .capsule
        config.attributedTitle = AttributedString(
            phrase,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .medium)])
        )
        button.configuration = config

        button.accessibilityLabel = phrase
        button.addTarget(self, action: #selector(initialPhraseTapped(_:)), for: .touchUpInside)

        return button
    }

    @objc private func initialPhraseTapped(_ sender: UIButton) {
        guard let phrase = sender.accessibilityLabel else { return }
        delegate?.suggestionBar(self, didSelectSuggestion: phrase)
    }

    private func createSuggestionContainer(for suggestion: String, isWord: Bool) -> UIView {
        let container = UIStackView()
        container.axis = .horizontal
        container.spacing = 2
        container.distribution = .fill

        // Check if this is a v11 format suggestion (contains /)
        let isV11Format = suggestion.contains("/")

        if isV11Format {
            // v11 format: display blocks inline
            let blocks = suggestion.split(separator: "/").map { String($0) }
            var cumulative = ""
            for block in blocks {
                cumulative += block
                let button = createInlineBlockButton(displayText: block, cumulativeText: cumulative)
                container.addArrangedSubview(button)
            }
        } else {
            // Standard format: display as-is
            let button = createWordButton(suggestion, fullSuggestion: suggestion, wordIndex: -1, rounded: isWord)
            container.addArrangedSubview(button)
        }

        return container
    }

    private func createInlineBlockButton(displayText: String, cumulativeText: String) -> UIButton {
        let button = UIButton(type: .system)

        var config = UIButton.Configuration.filled()
        if #available(iOS 13.0, *) {
            config.baseBackgroundColor = UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(red: 0.3, green: 0.3, blue: 0.32, alpha: 1.0)
                default:
                    return UIColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1.0)
                }
            }
            config.baseForegroundColor = UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return .white
                default:
                    return .black
                }
            }
        } else {
            config.baseBackgroundColor = UIColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1.0)
            config.baseForegroundColor = .black
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        config.cornerStyle = .medium
        config.attributedTitle = AttributedString(
            displayText,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .medium)])
        )
        button.configuration = config

        // Store cumulative text for selection
        button.accessibilityLabel = cumulativeText
        button.addTarget(self, action: #selector(inlineBlockTapped(_:)), for: .touchUpInside)

        return button
    }

    @objc private func inlineBlockTapped(_ sender: UIButton) {
        guard let cumulativeText = sender.accessibilityLabel else { return }
        delegate?.suggestionBar(self, didSelectSuggestion: cumulativeText)
    }

    private func createBlockSelectionButton(displayText: String, rawSuggestion: String, rounded: Bool) -> UIButton {
        let button = UIButton(type: .system)

        if rounded {
            var config = UIButton.Configuration.filled()
            if #available(iOS 13.0, *) {
                config.baseBackgroundColor = UIColor { traitCollection in
                    switch traitCollection.userInterfaceStyle {
                    case .dark:
                        return UIColor(red: 0.3, green: 0.3, blue: 0.32, alpha: 1.0)
                    default:
                        return UIColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0)
                    }
                }
                config.baseForegroundColor = UIColor { traitCollection in
                    switch traitCollection.userInterfaceStyle {
                    case .dark:
                        return .white
                    default:
                        return .black
                    }
                }
            } else {
                config.baseBackgroundColor = UIColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0)
                config.baseForegroundColor = .black
            }
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            config.cornerStyle = .capsule
            config.attributedTitle = AttributedString(
                displayText,
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .medium)])
            )
            button.configuration = config
        } else {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
            if #available(iOS 13.0, *) {
                config.baseForegroundColor = UIColor { traitCollection in
                    switch traitCollection.userInterfaceStyle {
                    case .dark:
                        return .white
                    default:
                        return .black
                    }
                }
            } else {
                config.baseForegroundColor = .black
            }
            config.attributedTitle = AttributedString(
                displayText,
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 16)])
            )
            button.configuration = config
        }

        // Store raw suggestion with slashes for block selection
        button.accessibilityLabel = rawSuggestion
        button.accessibilityHint = "v11_block"  // Marker for v11 format

        button.addTarget(self, action: #selector(blockSelectionButtonTapped(_:)), for: .touchUpInside)

        return button
    }

    @objc private func blockSelectionButtonTapped(_ sender: UIButton) {
        guard let rawSuggestion = sender.accessibilityLabel else { return }

        // Split by / to get blocks
        let blocks = rawSuggestion.split(separator: "/").map { String($0) }
        guard blocks.count > 1 else {
            // Only one block, just select it
            delegate?.suggestionBar(self, didSelectSuggestion: rawSuggestion.replacingOccurrences(of: "/", with: ""))
            return
        }

        // Show block selection overlay
        showBlockSelectionOverlay(blocks: blocks, sourceButton: sender)
    }

    private func showBlockSelectionOverlay(blocks: [String], sourceButton: UIButton) {
        // Remove existing overlay
        blockSelectionOverlay?.removeFromSuperview()

        // Create overlay container
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13.0, *) {
            overlay.backgroundColor = UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 0.98)
                default:
                    return UIColor(white: 1.0, alpha: 0.98)
                }
            }
        } else {
            overlay.backgroundColor = UIColor(white: 1.0, alpha: 0.98)
        }
        overlay.layer.cornerRadius = 12
        overlay.layer.shadowColor = UIColor.black.cgColor
        overlay.layer.shadowOpacity = 0.3
        overlay.layer.shadowOffset = CGSize(width: 0, height: 2)
        overlay.layer.shadowRadius = 8

        // Create horizontal scroll view for block buttons
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        overlay.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        // Create individual block buttons (tap = cumulative up to that block)
        for (index, block) in blocks.enumerated() {
            let cumulative = blocks[0...index].joined()
            let button = createBlockButton(displayText: block, cumulativeText: cumulative, blockIndex: index)
            stackView.addArrangedSubview(button)
        }

        // Add close button
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        closeButton.addTarget(self, action: #selector(closeBlockSelectionOverlay), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(closeButton)

        // Add to superview (keyboard view)
        if let keyboardView = superview {
            keyboardView.addSubview(overlay)
            blockSelectionOverlay = overlay

            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: keyboardView.leadingAnchor, constant: 8),
                overlay.trailingAnchor.constraint(equalTo: keyboardView.trailingAnchor, constant: -8),
                overlay.bottomAnchor.constraint(equalTo: self.topAnchor, constant: -4),
                overlay.heightAnchor.constraint(equalToConstant: 50),

                scrollView.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
                scrollView.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
                scrollView.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 4),
                scrollView.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -4),

                stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

                closeButton.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12),
                closeButton.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 30)
            ])
        }
    }

    private func createBlockButton(displayText: String, cumulativeText: String, blockIndex: Int) -> UIButton {
        let button = UIButton(type: .system)

        var config = UIButton.Configuration.filled()
        if #available(iOS 13.0, *) {
            config.baseBackgroundColor = UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1.0)
                default:
                    return UIColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1.0)
                }
            }
            config.baseForegroundColor = UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return .white
                default:
                    return .black
                }
            }
        } else {
            config.baseBackgroundColor = UIColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1.0)
            config.baseForegroundColor = .black
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        config.cornerStyle = .medium
        config.attributedTitle = AttributedString(
            displayText,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .medium)])
        )
        button.configuration = config

        // Store cumulative text for selection
        button.accessibilityLabel = cumulativeText
        button.tag = blockIndex
        button.addTarget(self, action: #selector(blockButtonTapped(_:)), for: .touchUpInside)

        return button
    }

    @objc private func blockButtonTapped(_ sender: UIButton) {
        guard let cumulativeText = sender.accessibilityLabel else { return }

        // Close overlay and send cumulative selection
        closeBlockSelectionOverlay()
        delegate?.suggestionBar(self, didSelectSuggestion: cumulativeText)
    }

    @objc private func closeBlockSelectionOverlay() {
        blockSelectionOverlay?.removeFromSuperview()
        blockSelectionOverlay = nil
    }

    private func createWordButton(_ word: String, fullSuggestion: String, wordIndex: Int = -1, rounded: Bool = false) -> UIButton {
        let button = UIButton(type: .system)

        if rounded {
            // Rounded button style for words (adaptive for light/dark mode)
            var config = UIButton.Configuration.filled()
            if #available(iOS 13.0, *) {
                config.baseBackgroundColor = UIColor { traitCollection in
                    switch traitCollection.userInterfaceStyle {
                    case .dark:
                        return UIColor(red: 0.3, green: 0.3, blue: 0.32, alpha: 1.0) // Dark mode
                    default:
                        return UIColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0) // Light mode
                    }
                }
                config.baseForegroundColor = UIColor { traitCollection in
                    switch traitCollection.userInterfaceStyle {
                    case .dark:
                        return .white // Dark mode text
                    default:
                        return .black // Light mode text
                    }
                }
            } else {
                config.baseBackgroundColor = UIColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0)
                config.baseForegroundColor = .black
            }
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            config.cornerStyle = .capsule
            config.attributedTitle = AttributedString(
                word,
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .medium)])
            )
            button.configuration = config
        } else {
            // Plain button style for sentence words (adaptive for light/dark mode)
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
            if #available(iOS 13.0, *) {
                config.baseForegroundColor = UIColor { traitCollection in
                    switch traitCollection.userInterfaceStyle {
                    case .dark:
                        return .white // Dark mode text
                    default:
                        return .black // Light mode text
                    }
                }
            } else {
                config.baseForegroundColor = .black
            }
            config.attributedTitle = AttributedString(
                word,
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 16)])
            )
            button.configuration = config
        }

        // Store full suggestion and word info
        button.accessibilityLabel = fullSuggestion
        button.tag = wordIndex

        button.addTarget(self, action: #selector(wordButtonTapped(_:)), for: .touchUpInside)

        return button
    }

    @objc private func wordButtonTapped(_ sender: UIButton) {
        guard let fullSuggestion = sender.accessibilityLabel else { return }
        let wordIndex = sender.tag

        if wordIndex >= 0 {
            // Partial selection: reconstruct suggestion up to this word
            let words = PunctuationProcessor.splitPunctuations(fullSuggestion)
            if wordIndex < words.count {
                let partial = words[0...wordIndex].joined()
                delegate?.suggestionBar(self, didSelectPartialSuggestion: partial, from: fullSuggestion)
            }
        } else {
            // Full suggestion selection
            delegate?.suggestionBar(self, didSelectSuggestion: fullSuggestion)
        }
    }
}

// MARK: - SuggestionBarDelegate Extension for backward compatibility
extension SuggestionBarDelegate {
    func suggestionBar(_ bar: SuggestionBar, didSelectPartialSuggestion partial: String, from fullSuggestion: String) {
        // Default implementation: treat as full suggestion
        suggestionBar(bar, didSelectSuggestion: partial)
    }
}
