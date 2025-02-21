from FlagEmbedding import BGEM3FlagModel
import numpy as np
from core.redis_client import RedisClient
import logging
import time
import psutil
import torch
import asyncio
logger = logging.getLogger(__name__)

class SemanticSearchEngine:
    _instance = None
    
    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance
    
    def __init__(self, model_name='BAAI/bge-m3'):
        if SemanticSearchEngine._instance is not None:
            raise Exception("SemanticSearchEngine is a singleton!")
            
        devices = 'cuda' if torch.cuda.is_available() else 'mps' if torch.backends.mps.is_available() else 'cpu'
        logger.info(f"Initializing SemanticSearchEngine with model: {model_name} on {devices}")
        self.model = BGEM3FlagModel(
            model_name, 
            use_fp16=True,
            devices=devices,
            return_dense=True,
            return_sparse=False,
            return_colbert_vecs=False,
        )
        logger.info("Model initialized")
        self.redis = RedisClient.get_instance()
        logger.debug("Redis instance obtained")
        self.index_name = 'idx:semantic_search'
        asyncio.create_task(self._create_index())
        SemanticSearchEngine._instance = self
        
    async def _create_index(self):
        """创建Redis搜索索引"""
        try:
            # 先删除可能存在的旧索引
            try:
                await self.redis.execute_command('FT.DROPINDEX', self.index_name)
            except:
                pass
                
            # 使用正确的维度配置
            vector_dim = 1024
            await self.redis.execute_command(
                'FT.CREATE', self.index_name, 
                'ON', 'HASH', 
                'PREFIX', '1', RedisClient.key('doc:'),
                'SCHEMA',
                'text', 'TEXT',
                'vector', 'VECTOR', 'HNSW', '6', 
                'TYPE', 'FLOAT32',
                'DIM', str(vector_dim),  # 确保是字符串
                'DISTANCE_METRIC', 'COSINE'
            )
            logger.info(f"Created semantic search index with vector dimension: {vector_dim}")
            
            # 验证索引创建
            info = await self.redis.execute_command('FT.INFO', self.index_name)
            info_dict = dict(zip(info[::2], info[1::2]))
            logger.info(f"Index created with config: {info_dict}")
            
        except Exception as e:
            logger.error(f"Failed to create index: {e}")
            raise

    async def generate_embedding(self, text: str) -> np.ndarray:
        """生成文本的向量表示"""
        try:
            start_time = time.time()
            embedding = self.model.encode([text])['dense_vecs'][0]
            end_time = time.time()
            logger.debug(f"Generated embedding for text: {text[:20]}... in {end_time - start_time:.2f} seconds, length: {len(embedding)}")
            return embedding
        except Exception as e:
            logger.error(f"Failed to generate embedding: {e}")
            raise

    async def store_embedding(self, doc_id: str, text: str, embedding: np.ndarray):
        """存储文档和其向量表示"""
        try:
            # 确保向量是float32类型
            embedding = embedding.astype(np.float32)
            key = RedisClient.key(f'doc:{doc_id}')
            
            # 先删除可能存在的旧数据
            await self.redis.delete(key)
            
            # 存储到Redis并添加到索引
            await self.redis.execute_command(
                'HSET', key,
                'text', text,
                'vector', embedding.tobytes()
            )
            
            # 验证索引状态
            info = await self.redis.execute_command('FT.INFO', self.index_name)
            info_dict = dict(zip(info[::2], info[1::2]))
            logger.debug(f"Index info after storage: num_docs={info_dict.get(b'num_docs', 0)}")
            
        except Exception as e:
            logger.error(f"Failed to store embedding for doc_id {doc_id}: {e}")
            raise

    async def search_similar(self, query_embedding: np.ndarray, top_k: int = 5, score_threshold: float = 0.5) -> list:
        """搜索相似文档
        Args:
            query_embedding: 查询向量
            top_k: 返回结果数量
            score_threshold: 相似度分数阈值 (余弦距离：0-1，越小表示越相似)
        """
        try:
            start_time = time.time()
            query_embedding = query_embedding.astype(np.float32)
            query = f'*=>[KNN {top_k} @vector $query_vector AS score]'
            results = await self.redis.execute_command(
                'FT.SEARCH', self.index_name,
                query,
                'PARAMS', 2, 'query_vector', query_embedding.tobytes(),
                'RETURN', 3, 'text', 'score', 'id',
                'SORTBY', 'score',
                'DIALECT', 2
            )
            
            parsed_results = []
            if results and len(results) > 1:  # 第一个元素是总数
                total_results = results[0]
                logger.debug(f"Total results found: {total_results}")
                
                # 从第二个元素开始遍历，每组包含 key 和 fields
                for i in range(1, len(results), 2):
                    key = results[i]  # 文档key
                    fields = results[i + 1]  # 字段列表
                    
                    # 将字段列表转换为字典
                    field_dict = {}
                    for j in range(0, len(fields), 2):
                        field_name = fields[j].decode() if isinstance(fields[j], bytes) else fields[j]
                        field_value = fields[j + 1].decode() if isinstance(fields[j + 1], bytes) else fields[j + 1]
                        field_dict[field_name] = field_value
                    
                    score = float(field_dict.get('score', 1.0))
                    if score <= score_threshold:
                        doc_id = key.decode().split(':')[-1] if isinstance(key, bytes) else key.split(':')[-1]
                        parsed_results.append({
                            'id': doc_id,
                            'text': field_dict['text'],
                            'score': score
                        })
                        logger.debug(f"Added result: id={doc_id}, score={score}")
            end_time = time.time()
            logger.info(f"Found {len(parsed_results)} similar documents within threshold {score_threshold} in {end_time - start_time:.4f} seconds")
            return parsed_results
            
        except Exception as e:
            logger.error(f"Search error: {e}")
            return []

# 测试代码
async def test_semantic_search():
    try:
        # 记录初始内存
        initial_memory = psutil.Process().memory_info().rss / 1024 / 1024
        logger.info(f"Initial memory usage: {initial_memory:.2f} MB")
        
        # 加载模型并记录内存变化
        engine = SemanticSearchEngine.get_instance()
        after_model_memory = psutil.Process().memory_info().rss / 1024 / 1024
        logger.info(f"Memory usage after model loading: {after_model_memory:.2f} MB")
        logger.info(f"Model memory impact: {(after_model_memory - initial_memory):.2f} MB")
        # Model memory impact: 428.52 MB, Generated embedding for text: 机器学习是人工智能的重要分支... in 0.56 seconds
        
        # 测试文档
        documents = [
            "机器学习是人工智能的重要分支",
            "深度学习是机器学习的子领域",
            "人工智能正在快速发展",
            "计算机视觉是一门赋予计算机“看”的能力的科学。它就像给机器安装了一双眼睛，让它们能像人类一样感知和理解这个世界。通过分析数字图像和视频，计算机视觉可以识别物体、场景、人脸，甚至可以理解图像中的动作和关系。这听起来很神奇，对吧？实际上，计算机视觉已经渗透到我们生活的方方面面。当你用手机解锁时，人脸识别技术就是计算机视觉在发挥作用；当你使用智能相册时，计算机视觉帮你自动分类照片；自动驾驶汽车能够安全行驶，也离不开计算机视觉的强大支持。那么，计算机视觉是如何做到的呢？它通过提取图像中的特征，如颜色、纹理、形状等，并利用复杂的数学模型和机器学习算法，来分析和理解这些特征。随着深度学习技术的快速发展，计算机视觉取得了突破性的进展，使得计算机能够以更高的准确度和效率完成各种视觉任务。计算机视觉的应用前景非常广阔。除了我们已经熟悉的领域，它还将在医疗、制造、农业等领域发挥重要作用。例如，计算机视觉可以帮助医生更准确地诊断疾病，可以提高工业生产的自动化水平，也可以帮助农民监测农作物的生长情况。总而言之，计算机视觉是一门充满活力和潜力的学科。它不仅推动了人工智能的发展，也深刻地改变了我们的生活方式。随着技术的不断进步，我们可以期待计算机视觉在未来为我们带来更多的惊喜。想了解更多吗？我们可以深入探讨计算机视觉的具体技术、应用案例，或者回答你关于计算机视觉的任何问题。",
            "今天的天气真的是很不错的, 阳光明媚, 万里无云",
        ]
        
        # 存储文档
        for i, text in enumerate(documents):
            embedding = await engine.generate_embedding(text)
            await engine.store_embedding(f"test_{i}", text, embedding)
        
        # 测试搜索
        query = "人工智能"
        query_embedding = await engine.generate_embedding(query)
        results = await engine.search_similar(query_embedding)
        
        print("\n语义搜索测试结果:")
        for result in results:
            print(f"ID: {result['id']}, Text: {result['text'][:20]}..., Score: {result['score']}")
            
    except Exception as e:
        logger.error(f"Test failed: {e}", exc_info=True)

if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG, 
        format='%(asctime)s - %(levelname)s [in %(pathname)s:%(lineno)d] - %(message)s')
    asyncio.run(test_semantic_search()) 