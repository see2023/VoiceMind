import re
import logging
from typing import List, Dict, Any, Tuple, Optional

logger = logging.getLogger(__name__)

class TextParser:
    """文本解析器，专门处理法律文档等结构化文本"""
    
    def __init__(self):
        # 章节条款的正则表达式
        self.chapter_pattern = re.compile(r'^第[一二三四五六七八九十百千零]+章\s*[　]*(.*?)$|^第(\d+)章\s*[　]*(.*?)$')
        self.section_pattern = re.compile(r'^第[一二三四五六七八九十零]+节\s*[　]*(.*?)$|^第(\d+)节\s*[　]*(.*?)$')
        self.article_pattern = re.compile(r'^第[一二三四五六七八九十百千零]+[十百千]?[一二三四五六七八九十零]?条\s*[　]*(.*?)$|^第(\d+)条\s*[　]*(.*?)$')
        
        # 目录识别
        self.toc_marker = re.compile(r'^目录\s*$', re.IGNORECASE)
        
        # 中文数字映射
        self.cn_nums = {
            '零': 0, '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, 
            '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
            '百': 100, '千': 1000
        }
    
    def _convert_cn_to_int(self, cn_num: str) -> int:
        """将中文数字转换为整数"""
        if cn_num.isdigit():
            return int(cn_num)
            
        result = 0
        temp = 0
        
        # 特殊情况处理：如果只有"零"
        if cn_num == "零":
            return 0
            
        for i, char in enumerate(cn_num):
            if char not in self.cn_nums:
                continue
                
            # 处理"零"
            if char == '零':
                continue
                
            # 处理数字
            if self.cn_nums[char] < 10:
                temp = self.cn_nums[char]
            # 处理十、百、千等单位
            else:
                # 如果前面没有数字，默认为1
                if temp == 0:
                    temp = 1
                result += temp * self.cn_nums[char]
                temp = 0
        
        # 处理最后一位数字
        if temp > 0:
            result += temp
            
        return result if result > 0 else temp
    
    def _extract_number_title(self, line: str, pattern: re.Pattern) -> Tuple[Optional[int], Optional[str]]:
        """从行中提取编号和标题"""
        match = pattern.match(line)
        if not match:
            return None, None
            
        # 处理中文数字格式
        if match.group(1) is not None:
            title = match.group(1) or ""  # 确保标题不为None
            # 提取中文数字部分
            num_part = re.search(r'第([一二三四五六七八九十百千零]+)', line).group(1)
            number = self._convert_cn_to_int(num_part)
        # 处理阿拉伯数字格式
        else:
            number = int(match.group(2))
            title = match.group(3) or ""  # 确保标题不为None
            
        return number, title
    
    def _is_toc_section(self, text: str, start_idx: int, end_idx: int) -> bool:
        """判断给定的文本段是否是目录部分"""
        # 如果明确包含"目录"标记
        for i in range(start_idx, min(start_idx + 20, end_idx)):  # 增加检查范围到20行
            if self.toc_marker.match(text.splitlines()[i].strip()):
                return True
                
        # 通过结构特征判断
        # 目录通常有连续的章节标记而没有正文内容
        lines = text.splitlines()[start_idx:end_idx]
        chapter_count = 0
        content_lines = 0
        
        for line in lines:
            line = line.strip()
            if not line:  # 跳过空行
                continue
                
            if self.chapter_pattern.match(line) or self.section_pattern.match(line) or self.article_pattern.match(line):
                chapter_count += 1
            else:
                # 计算非结构行的内容行数
                content_lines += 1
                
        # 提高对目录的判断能力 - 如果结构行比例高且内容行较少
        if chapter_count > 10 and chapter_count > content_lines * 0.7:
            return True
            
        return False
    
    def _find_toc_end(self, lines: List[str], start_idx: int) -> int:
        """查找目录部分的结束位置"""
        # 查找任何章节或条款的开始，而不仅仅是第一章
        for i in range(start_idx, len(lines)):
            line = lines[i].strip()
            if not line:  # 跳过空行
                continue
                
            # 检查是否是章节开始
            if (self.chapter_pattern.match(line) and ("第一章" in line or "第1章" in line)) or \
               (self.section_pattern.match(line) and ("第一节" in line or "第1节" in line)) or \
               (self.article_pattern.match(line) and ("第一条" in line or "第1条" in line)):
                return i
                
            # 额外判断：如果有连续超过5行都有章节号，而之后有正文，可能是目录结束
            if i > start_idx + 100:  # 如果已经检查了超过100行，避免无限检查
                consecutive_non_toc = 0
                for j in range(i, min(i+10, len(lines))):
                    if not (self.chapter_pattern.match(lines[j].strip()) or 
                            self.section_pattern.match(lines[j].strip()) or
                            self.article_pattern.match(lines[j].strip()) or
                            not lines[j].strip()):
                        consecutive_non_toc += 1
                if consecutive_non_toc > 5:
                    return i
        
        # 如果没找到明确的目录结束，但目录超过了一定长度，可能需要强制结束
        if len(lines) > start_idx + 200:  # 如果目录已经超过200行
            return min(start_idx + 200, len(lines) - 1)
            
        return start_idx  # 默认返回开始位置，表示没找到目录
    
    def parse_document(self, text: str) -> Dict[str, Any]:
        """解析文档，返回结构化数据"""
        lines = text.splitlines()
        result = {
            "structure": [],  # 文档结构
            "chunks": []      # 文档块
        }
        
        # 跳过目录部分
        start_idx = 0
        if len(lines) > 20 and self._is_toc_section(text, 0, min(200, len(lines))):  # 增加检查范围到200行
            start_idx = self._find_toc_end(lines, 0)
            logger.info(f"检测到目录，跳过前 {start_idx} 行")
        
        current_chapter = None
        current_section = None
        current_article = None
        current_content = []
        
        # 遍历行
        for i in range(start_idx, len(lines)):
            line = lines[i].strip()
            if not line:
                continue
            
            # 检查是否是章
            chapter_num, chapter_title = self._extract_number_title(line, self.chapter_pattern)
            if chapter_num is not None:
                # 保存之前的内容
                if current_article and current_content:
                    chunk_id = f"c{current_chapter['number']}"
                    if current_section:
                        chunk_id += f"_s{current_section['number']}"
                    chunk_id += f"_a{current_article['number']}"
                    
                    result["chunks"].append({
                        "id": chunk_id,
                        "text": "\n".join(current_content),
                        "hierarchy": [
                            {"level": 1, "title": current_chapter['title'], "number": current_chapter['number']},
                            {"level": 2, "title": current_section['title'], "number": current_section['number']} if current_section else None,
                            {"level": 3, "title": current_article['title'], "number": current_article['number']}
                        ]
                    })
                    current_content = []
                
                # 开始新的章
                current_chapter = {"number": chapter_num, "title": chapter_title}
                current_section = None
                current_article = None
                
                # 添加到结构中
                result["structure"].append({
                    "level": 1,
                    "number": chapter_num,
                    "title": chapter_title,
                    "children": []
                })
                continue
            
            # 检查是否是节
            section_num, section_title = self._extract_number_title(line, self.section_pattern)
            if section_num is not None and current_chapter:
                # 保存之前的内容
                if current_article and current_content:
                    chunk_id = f"c{current_chapter['number']}"
                    if current_section:
                        chunk_id += f"_s{current_section['number']}"
                    chunk_id += f"_a{current_article['number']}"
                    
                    result["chunks"].append({
                        "id": chunk_id,
                        "text": "\n".join(current_content),
                        "hierarchy": [
                            {"level": 1, "title": current_chapter['title'], "number": current_chapter['number']},
                            {"level": 2, "title": current_section['title'], "number": current_section['number']} if current_section else None,
                            {"level": 3, "title": current_article['title'], "number": current_article['number']}
                        ]
                    })
                    current_content = []
                
                # 开始新的节
                current_section = {"number": section_num, "title": section_title}
                current_article = None
                
                # 添加到结构中
                if result["structure"]:
                    result["structure"][-1]["children"].append({
                        "level": 2,
                        "number": section_num,
                        "title": section_title,
                        "children": []
                    })
                continue
            
            # 检查是否是条
            article_num, article_title = self._extract_number_title(line, self.article_pattern)
            if article_num is not None and current_chapter:
                # 保存之前的内容
                if current_article and current_content:
                    chunk_id = f"c{current_chapter['number']}"
                    if current_section:
                        chunk_id += f"_s{current_section['number']}"
                    chunk_id += f"_a{current_article['number']}"
                    
                    # 把完整内容作为text保存，而不是只用第一行
                    full_text = "\n".join(current_content)
                    
                    result["chunks"].append({
                        "id": chunk_id,
                        "text": full_text,
                        "hierarchy": [
                            {"level": 1, "title": current_chapter['title'], "number": current_chapter['number']},
                            {"level": 2, "title": current_section['title'], "number": current_section['number']} if current_section else None,
                            {"level": 3, "title": f"第{article_num}条", "number": current_article['number']}  # 只使用条号作为标题
                        ]
                    })
                    current_content = []
                
                # 开始新的条 - 只存储条号，不把内容放在标题中
                current_article = {"number": article_num, "title": f"第{article_num}条"}
                current_content = [line]  # 存储完整行作为内容
                
                # 添加到结构中 - 修改结构的标题
                if result["structure"]:
                    article_node = {
                        "level": 3,
                        "number": article_num,
                        "title": f"第{article_num}条"  # 只使用条号
                    }
                    
                    if current_section and result["structure"][-1]["children"]:
                        result["structure"][-1]["children"][-1]["children"].append(article_node)
                    else:
                        result["structure"][-1]["children"].append(article_node)
                continue
            
            # 普通内容，添加到当前条款的内容中
            if current_article:
                current_content.append(line)
        
        # 处理最后一个条款的内容
        if current_article and current_content:
            chunk_id = f"c{current_chapter['number']}"
            if current_section:
                chunk_id += f"_s{current_section['number']}"
            chunk_id += f"_a{current_article['number']}"
            
            result["chunks"].append({
                "id": chunk_id,
                "text": "\n".join(current_content),
                "hierarchy": [
                    {"level": 1, "title": current_chapter['title'], "number": current_chapter['number']},
                    {"level": 2, "title": current_section['title'], "number": current_section['number']} if current_section else None,
                    {"level": 3, "title": current_article['title'], "number": current_article['number']}
                ]
            })
        
        # 清理结构中的 None 值和确保元数据类型正确
        for chunk in result["chunks"]:
            # 过滤None值
            chunk["hierarchy"] = [h for h in chunk["hierarchy"] if h is not None]
            
            # 确保所有层级项都有标准类型的值
            for item in chunk["hierarchy"]:
                # 确保标题是字符串
                if "title" in item and item["title"] is None:
                    item["title"] = ""  # 用空字符串替代None
                
                # 确保编号是整数或字符串
                if "number" in item and item["number"] is None:
                    item["number"] = 0  # 用0替代None
        
        return result


def parse_text(text: str) -> Dict[str, Any]:
    """解析文本文档，返回结构化数据"""
    try:
        parser = TextParser()
        return parser.parse_document(text)
    except Exception as e:
        logger.error(f"解析文档失败: {e}")
        return {"error": str(e)}


def parse_file(file_path: str) -> Dict[str, Any]:
    """解析文本文件，返回结构化数据"""
    with open(file_path, 'r', encoding='utf-8') as f:
        text = f.read()
    return parse_text(text) 