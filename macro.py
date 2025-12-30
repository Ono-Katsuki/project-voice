# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Library to call generative AI.
"""

import difflib
import json
import os
import re
from concurrent.futures import ThreadPoolExecutor, as_completed

import jinja2
from google import genai
from google.genai import types

# Tuned model configurations (Vertex AI endpoints)
TUNED_MODELS = {
    'voice-v11': {
        'project_id': 'project-voice-476504',
        'location': 'us-central1',
        'endpoint': 'projects/700129023625/locations/us-central1/endpoints/2546212743719944192',
    },
}

# v11 prompt header
V11_PROMPT_HEADER = (
    "キーボードの予測変換として[---]に続く言葉を予測変換してください。"
    "[---]より前はこれまでのユーザー入力です。\n"
    "ユーザー入力と予測変換の間には境界 [---]を入れてください。"
)
V11_MARKER_LINE = "ーーーー以下が予測変換対象ーーーー"

# 8 tone prompts for v11
V11_TONE_PROMPTS = {
    'dev': (
        "【トーン: dev】開発の文脈で予測変換してください。"
        "開発寄り語彙（例: PR/レビュー/デプロイ/issue/バグ/再現/修正/ログ/確認）を優先。"
        "語尾はフラットで自然（です/ますでも可）。"
        "同じ語句や同じ文の繰り返しは禁止。"
        "[---]より前は一文字も変更せず、[---]より後のみを / 区切りで出力してください。"
    ),
    'meeting': (
        "【トーン: meeting】ミーティングの文脈で予測変換してください。"
        "会議語彙（例: 議題/アジェンダ/共有/確認事項/宿題/決定/進捗/次回）を優先。"
        "結びは『〜します』『〜しましょう』『〜いかがでしょうか』など会議っぽく。"
        "同じ語句や同じ文の繰り返しは禁止。"
        "[---]より前は一文字も変更せず、[---]より後のみを / 区切りで出力してください。"
    ),
    'casual': (
        "【トーン: casual】カジュアルな文脈で予測変換してください。"
        "砕けた口語（例: だよ/だね/しよ/しよう/かな/だと思う）を優先し、敬語はなるべく避ける。"
        "ただし乱暴な表現は避けて自然に。"
        "同じ語句や同じ文の繰り返しは禁止。"
        "[---]より前は一文字も変更せず、[---]より後のみを / 区切りで出力してください。"
    ),
    'business': (
        "【トーン: business】ビジネスの文脈で予測変換してください。"
        "実務的で丁寧（例: 恐れ入りますが/ご確認のほど/差し支えなければ/よろしくお願いいたします）を優先。"
        "長くなりすぎないように [---]より後は原則 20 トークン（/区切りで20個）以内を目安。"
        "同じ語句や同じ文の繰り返しは禁止。"
        "[---]より前は一文字も変更せず、[---]より後のみを / 区切りで出力してください。"
    ),
    'polite': (
        "【トーン: polite】丁寧・敬語の文脈で予測変換してください。"
        "です/ます調＋クッション言葉（例: お手数ですが/恐れ入りますが/ありがとうございます）を優先。"
        "ビジネスほど堅くしすぎず、丁寧さを保った自然文に。"
        "同じ語句や同じ文の繰り返しは禁止。"
        "[---]より前は一文字も変更せず、[---]より後のみを / 区切りで出力してください。"
    ),
    'friendly': (
        "【トーン: friendly】親しみやすい文脈で予測変換してください。"
        "柔らかい語尾（例: 〜ですね/〜だと嬉しいです/〜しよう）や感謝を入れてもよい。"
        "ただし過剰に長くしない。"
        "同じ語句や同じ文の繰り返しは禁止。"
        "[---]より前は一文字も変更せず、[---]より後のみを / 区切りで出力してください。"
    ),
    'concise': (
        "【トーン: concise】短く要点だけの文脈で予測変換してください。"
        "冗長な前置きは避け、[---]より後は原則 8〜12 トークン（/区切りで8〜12個）程度を目安に短く。"
        "敬語は必要最低限に。"
        "同じ語句や同じ文の繰り返しは禁止。"
        "[---]より前は一文字も変更せず、[---]より後のみを / 区切りで出力してください。"
    ),
    'enthusiastic': (
        "【トーン: enthusiastic】明るく前向きな文脈で予測変換してください。"
        "前向き語彙（例: いいですね/助かります/楽しみ/最高/嬉しい）を適度に使い、"
        "必要なら『！』を1個だけ入れてもよい（多用しない）。"
        "同じ語句や同じ文の繰り返しは禁止。"
        "[---]より前は一文字も変更せず、[---]より後のみを / 区切りで出力してください。"
    ),
}

# Temperature by tone
V11_TONE_TEMPERATURES = {
    'dev': 0.28,
    'meeting': 0.25,
    'casual': 0.55,
    'business': 0.20,
    'polite': 0.22,
    'friendly': 0.35,
    'concise': 0.20,
    'enthusiastic': 0.65,
}

# Setup Jinja2 environment
# trim_blocks: the first newline after a template tag is removed
# lstrip_blocks: strip tabs and spaces from the beginning of a line to the start of a block
JINJA_ENV = jinja2.Environment(
    loader=jinja2.FileSystemLoader(
        os.path.join(os.path.dirname(__file__), 'templates', 'prompts')),
    trim_blocks=True,
    lstrip_blocks=True)


def _build_v11_prompt(history, last_sentence, prefix, tone_prompt,
                      persona='', conversation_history='', emotion=''):
  """Build v11 format prompt with tone.

  Args:
    history: The context before the last sentence (for reference)
    last_sentence: The last sentence being typed (prediction target)
    prefix: The conversion target prefix after [---]
    tone_prompt: The tone-specific prompt
    persona: User persona description
    conversation_history: Recent conversation history
    emotion: Sentence emotion (statement, question, request, negative)

  Returns:
    Formatted prompt string
  """
  # Build supplementary sections
  sections = []

  if persona:
    sections.append(f"<ペルソナ>\n{persona}")

  if conversation_history:
    sections.append(f"<会話履歴>\n{conversation_history}")

  if emotion and emotion != 'statement':
    emotion_labels = {
        'question': '質問文',
        'request': '依頼・お願い',
        'negative': '否定文'
    }
    emotion_label = emotion_labels.get(emotion, emotion)
    sections.append(f"<文のタイプ>\n{emotion_label}")

  if history:
    sections.append(f"<文脈>\n{history}")

  context_section = ""
  if sections:
    context_section = "\n" + "\n\n".join(sections) + "\n"

  return f"{V11_PROMPT_HEADER}\n{tone_prompt}{context_section}\n{V11_MARKER_LINE}\n{last_sentence}[---]{prefix}"


def _parse_v11_output(output_text):
  """Parse v11 output and return the prediction string after [---].

  Returns the slash-separated tokens as-is for block selection on client.
  """
  if not output_text or '[---]' not in output_text:
    return None
  _, after_marker = output_text.split('[---]', 1)
  # Keep slash-separated format for block selection
  tokens = [t.strip() for t in after_marker.split('/') if t.strip()]
  if not tokens:
    return None
  # Return with / delimiter preserved
  return '/'.join(tokens)


def _similarity(a, b):
  """Calculate similarity between two strings using SequenceMatcher."""
  if not a or not b:
    return 0.0
  return difflib.SequenceMatcher(None, a, b).ratio()


def _select_diverse_suggestions(suggestions, num_select=4):
  """Select most diverse suggestions using greedy selection.

  Args:
    suggestions: List of (tone_id, suggestion_text) tuples.
    num_select: Number of suggestions to select.

  Returns:
    List of selected suggestion texts.
  """
  if len(suggestions) <= num_select:
    return [s[1] for s in suggestions]

  # Greedy selection: start with the first one, then pick most different
  selected = [suggestions[0]]
  remaining = suggestions[1:]

  while len(selected) < num_select and remaining:
    best_idx = -1
    best_min_sim = 1.0

    for i, (_, candidate) in enumerate(remaining):
      # Calculate minimum similarity to all selected
      min_sim = min(_similarity(candidate, sel[1]) for sel in selected)
      # We want to maximize diversity (minimize similarity)
      if min_sim < best_min_sim:
        best_min_sim = min_sim
        best_idx = i

    if best_idx >= 0:
      selected.append(remaining[best_idx])
      remaining.pop(best_idx)
    else:
      break

  return [s[1] for s in selected]


def _generate_one_tone(client, endpoint, history, last_sentence, prefix, tone_id,
                       persona='', conversation_history='', emotion=''):
  """Generate prediction for one tone."""
  tone_prompt = V11_TONE_PROMPTS.get(tone_id, '')
  temperature = V11_TONE_TEMPERATURES.get(tone_id, 0.3)
  prompt = _build_v11_prompt(history, last_sentence, prefix, tone_prompt,
                             persona, conversation_history, emotion)

  # Debug: log prompt for first tone only
  if tone_id == 'neutral':
    print(f'[DEBUG v11] history={repr(history[:50] if history else "")}', flush=True)
    print(f'[DEBUG v11] last_sentence={repr(last_sentence[:50] if last_sentence else "")}', flush=True)
    print(f'[DEBUG v11] prefix={repr(prefix)}', flush=True)
    print(f'[DEBUG v11] persona={repr(persona[:30] if persona else "")}', flush=True)
    print(f'[DEBUG v11] emotion={repr(emotion)}', flush=True)
    print(f'[DEBUG v11] prompt preview: {repr(prompt[:200])}', flush=True)

  try:
    response = client.models.generate_content(
        model=endpoint,
        contents=prompt,
        config=types.GenerateContentConfig(
            temperature=temperature,
            max_output_tokens=96,
            thinking_config=types.ThinkingConfig(thinking_budget=0),
        ),
    )
    if response.text:
      prediction = _parse_v11_output(response.text.strip())
      if prediction:
        return (tone_id, prediction)
  except Exception as e:
    print(f'[WARN] Tone {tone_id} failed: {e}')
  return None


def RunTunedModel(model_id, user_inputs, temperature):
  """Runs a tuned model via Vertex AI with 8 tones in parallel.

  Generates predictions for all 8 tones in parallel, then selects
  the 3 most diverse suggestions.

  Args:
    model_id: The tuned model ID (e.g., 'voice-v11').
    user_inputs: Dictionary containing v11_context and v11_prefix.
    temperature: Controls the randomness (not used, per-tone temps are used).

  Returns:
    JSON string with suggestions in the standard format.
  """
  config = TUNED_MODELS.get(model_id)
  if not config:
    return json.dumps({'messages': []})

  # Get v11 format parameters
  # v11_history: context before the last sentence (for reference)
  # v11_last_sentence: the last sentence being typed (without prefix)
  # v11_prefix: the keyboard input to be converted (hiragana/alphabet)
  history = user_inputs.get('v11_history', '')
  last_sentence = user_inputs.get('v11_last_sentence', '')
  prefix = user_inputs.get('v11_prefix', '')

  # Fallback: if new params not provided, use legacy v11_context
  if not last_sentence and not prefix:
    context = user_inputs.get('v11_context', '')
    if context:
      last_sentence = context
    else:
      text = user_inputs.get('text', '')
      last_sentence = text

  # Get supplementary context
  persona = user_inputs.get('persona', '')
  conversation_history = user_inputs.get('conversationHistory', '')
  emotion = user_inputs.get('sentenceEmotion', '')

  # Debug: log ALL user_inputs keys and values
  print(f'[DEBUG v11] ALL KEYS: {list(user_inputs.keys())}', flush=True)
  for k, v in user_inputs.items():
    val_preview = repr(v[:50]) if v and len(v) > 50 else repr(v)
    print(f'[DEBUG v11] {k}={val_preview}', flush=True)

  # Create Vertex AI client
  client = genai.Client(
      vertexai=True,
      project=config['project_id'],
      location=config['location']
  )

  endpoint = config['endpoint']
  tone_ids = list(V11_TONE_PROMPTS.keys())

  # Generate all 8 tones in parallel
  suggestions = []
  with ThreadPoolExecutor(max_workers=8) as executor:
    futures = {
        executor.submit(_generate_one_tone, client, endpoint, history, last_sentence, prefix, tone_id,
                        persona, conversation_history, emotion): tone_id
        for tone_id in tone_ids
    }
    for future in as_completed(futures):
      result = future.result()
      if result:
        suggestions.append(result)

  if not suggestions:
    return json.dumps({'messages': []})

  # Select 3 most diverse suggestions
  selected = _select_diverse_suggestions(suggestions, num_select=3)

  # Debug: log selected suggestions
  print(f'[DEBUG v11] selected suggestions: {selected}', flush=True)

  # Format as numbered list
  numbered_list = '\n'.join(f'{i+1}. {s}' for i, s in enumerate(selected))
  return json.dumps({'messages': [{'text': numbered_list}]}, ensure_ascii=False)


def RunGeminiMacro(model_id, prompt, temperature, language):
  """Runs a Gemini macro.

  This function calls a Gemini macro with the specified parameters.

  Args:
    model_id: The ID of the Gemini model to use.
    prompt: The input text or prompt for the macro.
    temperature: Controls the randomness of the output.
      Higher values (e.g., 0.8) make the output more random and creative,
      while lower values (e.g., 0.2) make it more focused and deterministic.
    language: The language to use for the macro.

  Returns:
    The result generated by the macro.
  """

  client = genai.Client(api_key=os.environ.get('API_KEY'))
  thinking_config = None
  if model_id.startswith('gemini-2.5-'):
    thinking_config = types.ThinkingConfig(thinking_budget=0)
  response = client.models.generate_content(
      model=model_id,
      contents=prompt,
      config=types.GenerateContentConfig(
          temperature=temperature,
          top_p=0.5,
          safety_settings=[
              types.SafetySetting(
                  category='HARM_CATEGORY_HATE_SPEECH', threshold='BLOCK_NONE'),
              types.SafetySetting(
                  category='HARM_CATEGORY_SEXUALLY_EXPLICIT',
                  threshold='BLOCK_NONE'),
          ],
          thinking_config=thinking_config,
      ),
  )
  if not response.text:
    return json.dumps({'messages': []})
  text = response.text
  # Quick hack to remove highlights from response. All '*' are removed even
  # if they are not highlights.
  text = text.replace('*', '')
  if language == 'Japanese':
    # Also remove hankaku spaces in Japanese texts.
    text = re.sub(r'([^\w;:,.?]) +(\W)', r'\1\2', text, flags=re.ASCII)
  text = text.replace('§', ' ')
  return json.dumps({'messages': [{'text': text}]}, ensure_ascii=False)


def RunMacro(macro_id, user_inputs, temperature, model_id):
  """Runs a LLM macro with user inputs.

  Replaces placeholders in a template with user inputs and calls the macro.

  Args:
    macro_id: Macro ID.
    user_inputs: Dictionary of user inputs.
    temperature: Controls the randomness of the output.
      Higher values (e.g., 0.8) make the output more random and creative,
      while lower values (e.g., 0.2) make it more focused and deterministic.
    model_id: The ID of the generative AI model to use.

  Returns:
    The result of the macro call.
  """

  # Check if this is a tuned model
  if model_id in TUNED_MODELS:
    return RunTunedModel(model_id, user_inputs, temperature)

  # Handle space character for Japanese language
  language = user_inputs.get('language', '')
  for key in user_inputs:
    user_input = user_inputs[key]
    if key == 'text' and language == 'Japanese':
      user_input = user_input.replace(' ', '§')
    # Replace ' ' in between with '§' for word macro as it produces better
    # results.
    # TODO: Improve the word macro and remove this hack.
    if key == 'text' and macro_id == 'WordGeneric20240628':
      user_input = re.sub(r'§$', ' ', user_input.replace(' ', '§'))
    user_inputs[key] = user_input

  prompt = JINJA_ENV.get_template(macro_id + '.jinja2').render(user_inputs)

  return RunGeminiMacro(model_id, prompt, temperature, language)
