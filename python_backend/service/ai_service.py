import base64
import logging
import os
import asyncio
from typing import List
from service.ai_models import Message, MessageRole
from config.config_manager import config
import openai
from tools.image_tools import image_file_to_base64
from PIL import Image
logger = logging.getLogger(__name__)

class AIService:
    def __init__(self, max_images: int = 2, base_url: str = None, api_key: str = None):
        if not base_url:
            base_url = config.llm.get('openai_custom_url')
        self._base_url = base_url
        if not api_key:
            api_key = os.getenv(config.llm.get('openai_custom_key_envname'))
        self._client = openai.AsyncOpenAI(api_key=api_key, base_url=self._base_url)
        logger.debug(f"AIService init, base_url: {self._base_url}, api_key: {api_key}")
        self._max_images = max_images

    def _process_messages(self, messages: List[Message]) -> List[Message]:
        """Process messages to ensure image count is within limits"""
        image_count = 0
        for msg in messages:
            if isinstance(msg.content, list):
                for item in msg.content:
                    if isinstance(item, dict) and item.get('type') == "image_url":
                        image_count += 1
                        
        if image_count > self._max_images:
            while image_count > self._max_images:
                for msg in messages:
                    if isinstance(msg.content, list):
                        for item in msg.content:
                            if isinstance(item, dict) and item.get('type') == "image_url":
                                msg.content.remove(item)
                                image_count -= 1
                                logger.debug(f"Remove image, current image_count: {image_count}")
                                break
                    if image_count <= self._max_images:
                        break
        return messages

    async def generate_response(self, messages: List[dict], model: str = None, json_mode: bool = False) -> str:
        """处理消息列表并生成响应"""
        try:
            # 转换消息格式
            formatted_messages = []
            for msg in messages:
                role = msg.get('role', 'user')
                content = msg.get('content', '')
                formatted_messages.append(Message(
                    role=MessageRole[role],
                    content=content
                ))

            # 调用现有的生成方法
            return await self.generate_response_formatted(
                formatted_messages,
                model=model,
                json_mode=json_mode
            )
        except Exception as e:
            logger.error(f'Error generating response: {e}')
            raise

    async def generate_response_formatted(self, messages: List[Message], model: str = None, json_mode: bool = False) -> str:
        """原有的 generate_response 方法，重命名为内部方法"""
        messages = self._process_messages(messages)
        try:
            kwargs = {
                "model": model,
                "messages": [message.to_dict() for message in messages],
            }
            
            # Add response_format if json_mode is enabled and supported
            if json_mode and config.llm.get('support_json_mode', False):
                kwargs["response_format"] = {"type": "json_object"}
                
            # Add timeout to the request
            response = await asyncio.wait_for(
                self._client.chat.completions.create(**kwargs),
                timeout=90
            )
            
            logger.debug('response: %s', response)
            logger.debug(f"Token usage - Input: {response.usage.prompt_tokens}, "
                         f"Output: {response.usage.completion_tokens}, "
                         f"Total: {response.usage.total_tokens}")
            
            return response.choices[0].message.content
        except asyncio.TimeoutError:
            logger.error(f'Timeout occurred after 90 seconds while sending message to {self._base_url}')
            return ''
        except Exception as e:
            logger.error(f'send message to {self._base_url} error: {e}')
            return ''

    async def generate_response_stream(self, messages: List[Message], model: str = "Qwen/Qwen2-VL-2B-Instruct-AWQ"):
        """Stream version of generate_response"""
        messages = self._process_messages(messages)
        try:
            response_stream = await self._client.chat.completions.create(
                model=model,
                messages=[message.to_dict() for message in messages],
                stream=True,
                # stream_options = {
                #     "include_usage": True
                # }
            )
            # total_prompt_tokens = 0
            # total_completion_tokens = 0
            async for chunk in response_stream:
                # if hasattr(chunk, 'usage') and chunk.usage:
                #     total_prompt_tokens = chunk.usage.prompt_tokens
                #     total_completion_tokens = chunk.usage.completion_tokens
                if chunk.choices[0].delta.content:
                    yield chunk.choices[0].delta.content

            # logger.debug(f"Stream response token usage - Input: {total_prompt_tokens}, "
            #              f"Output: {total_completion_tokens}, "
            #              f"Total: {total_prompt_tokens + total_completion_tokens}")
        except Exception as e:
            logger.error(f'Stream response error: {e}')
            yield f"Error: {str(e)}"

    async def ocr(self, image_path: str = None, image_content_base64: str = None, model: str = "Qwen/Qwen2-VL-2B-Instruct-AWQ") -> str:
        image_base64 = None
        if image_path:
            image_base64 = image_file_to_base64(image_path) 
        elif image_content_base64:
            image_base64 = image_content_base64
        else:
            raise ValueError("image_path or image_content is required")
        messages = [
            Message(role=MessageRole.system, content="""You are a professional OCR model. Your task is to accurately recognize and output ALL text from images, especially Chinese text.
Requirements:
1. Maintain the original text format and layout
2. Recognize ALL text completely, including Chinese characters, numbers, and punctuation
3. Do not skip any text or characters
4. For image-text combinations, focus on actual text content
5. Output raw text only, no explanations"""),
            
            Message(role=MessageRole.user, content=[
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"}},
                {"type": "text", "text": "Extract text from this social media content image. Focus on Chinese text recognition."}
            ]),
        ]
        
        try:
            response = await self.generate_response_formatted(messages, model=model)
            if not response.strip():  # 如果返回为空或者只有空白字符
                logger.warning("OCR returned empty result, retrying...")
                response = await self.generate_response_formatted(messages, model=model)  # 简单的重试一次
            return response
        except Exception as e:
            logger.error(f"OCR failed: {str(e)}")
            raise
        



async def main():
    # 配置日志
    logging.basicConfig(level=logging.DEBUG, 
        format='%(asctime)s - %(levelname)s [in %(pathname)s:%(lineno)d] - %(message)s')
    ai_service = AIService()
    if False:
        # 使用 os.path.expanduser() 展开 ~ 符号
        image_path3 = os.path.expanduser("~/Pictures/boy3.jpg")
        image_path2 = os.path.expanduser("~/Pictures/boy2.jpg")
        image_path1 = os.path.expanduser("~/Pictures/boy1.jpg")
        logging.info(f"Image path: {image_path3}")

        # 将图片转换为base64
        image_base64_3 = image_file_to_base64(image_path3)
        logging.debug(f"Image base64: {image_base64_3[:50]}...")  # 只打印前50个字符
        image_base64_2 = image_file_to_base64(image_path2)
        image_base64_1 = image_file_to_base64(image_path1)

        # 创建 Message 对象
        messages = [
            Message(
                role=MessageRole.system,
                content="你是一个儿童心理学家，请根据图片中的孩子回答问题。"
            ),
            Message(
                role=MessageRole.user,
                content=[
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_base64_3}"}},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_base64_2}"}},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_base64_1}"}},
                {"type": "text", "text": "图中的孩子们在干嘛？他们坐的端正吗？他们开心吗？"}
            ]
            )
        ]
        response = await ai_service.generate_response_formatted(messages, model=config.llm.get('openai_custom_mm_model'))
        logging.info(f"Response: {response}")

    if False:
        ocr_image_path = os.path.expanduser("~/Pictures/exam_en.jpg")
        response = await ai_service.ocr(image_path=ocr_image_path, model=config.llm.get('openai_custom_mm_model'))
        logging.info(f"OCR Response: {response}")
    
    if True: # basic llm test
        messages = [
            Message(role=MessageRole.system, content="You are a funny guy, and you are a good friend of the user."),
            Message(role=MessageRole.user, content="你给我讲个笑话吧，关于下雨天的。"),
        ]
        response = await ai_service.generate_response_formatted(messages, model=config.llm.get('model'))
        logging.info(f"Response: {response}")

if __name__ == "__main__":
    asyncio.run(main())
