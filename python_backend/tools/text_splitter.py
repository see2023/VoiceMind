import re
from typing import List, Tuple, Dict
from dataclasses import dataclass

@dataclass
class Token:
    text: str
    is_punctuation: bool
    is_emoji: bool
    is_english_word: bool = False  # 新增：是否为英文单词

def split_text(text: str, skip_emojis: bool = True) -> List[Token]:
    """
    将输入文本分割成单个字符/单词/标点/表情符号
    
    Args:
        text: 输入文本字符串
    
    Returns:
        List[Token]: 分割后的标记列表，每个标记包含文本内容和类型标记
    """
    # 定义标点符号集合（中英文标点）
    punctuation = set('''，。！？；：、．,.:;!?()[]{}'"…''')
    
    # 定义表情符号集合（从原代码中提取）
    emojis = {
        "😊", "😔", "😡", "😰", "🤢", "😮", "🎼", 
        "👏", "😀", "😭", "🤧", "😷", "❓"
    }
    
    tokens = []
    i = 0
    while i < len(text):
        char = text[i]
        # 跳过空格
        if char.isspace():
            i += 1
            continue

        # 如果是表情符号
        if char in emojis:
            if not skip_emojis:
                tokens.append(Token(char, False, True))
            i += 1
            continue

        # 如果是标点符号
        if char in punctuation:
            tokens.append(Token(char, True, False))
            i += 1
            continue

        # 如果是英文字母，连续累积
        if re.match(r'[a-zA-Z]', char):
            start = i
            while i < len(text) and re.match(r'[a-zA-Z]', text[i]):
                i += 1
            english_word = text[start:i]
            tokens.append(Token(english_word, False, False, True))
            continue

        # 其他字符（例如中文）逐个处理
        tokens.append(Token(char, False, False, False))
        i += 1

    return tokens 

if __name__ == "__main__":
      # 测试用例1：纯中文
    text1 = "你好，世界！这是一个测试。"
    tokens1 = split_text(text1)
    print("测试1 - 纯中文：")
    print(tokens1)
    print()

    # 测试用例2：纯英文
    text2 = "Hello, world! This is a test."
    tokens2 = split_text(text2)
    print("测试2 - 纯英文：")
    print(tokens2)
    print()

    # 测试用例3：带表情符号
    text3 = "今天心情很好😊，大家一起鼓掌吧👏！"
    tokens3 = split_text(text3)
    print("测试3 - 带表情：")
    print(tokens3)
    print()

    # 测试用例4：中英混合
    text4 = "在英文里，美丽就是beautiful。"
    tokens4 = split_text(text4)
    print("测试4 - 中英混合：")
    print(tokens4)