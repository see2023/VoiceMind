import 'package:get/get.dart';

class Messages extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
        'en_US': {
          // 应用标题
          'app_title': 'Meeting Assistant',

          // 通用
          'error': 'Error',
          'save': 'Save',
          'cancel': 'Cancel',
          'success': 'Success',
          'settings_saved': 'Settings saved',
          'settings_save_failed': 'Failed to save settings',
          'refresh': 'Refresh',
          'close': 'Close',
          'delete': 'Delete',
          'edit': 'Edit',
          'preview': 'Preview',
          'title': 'Title',
          'description': 'Description',
          'status': 'Status',
          'untitled': 'Untitled',
          'unknown': 'Unknown',
          'confirm_delete': 'Confirm Delete',

          // 会议信息
          'meeting_info': 'Meeting Info',
          'meeting_title': 'Meeting Title',
          'meeting_title_hint': 'Enter meeting title',
          'meeting_objective': 'Core Objective',
          'meeting_objective_hint': 'Describe meeting objective',
          'meeting_notes': 'Important Notes',
          'meeting_notes_hint': 'Time limits, special requirements, etc.',
          'untitled_meeting': 'Untitled Meeting',
          'edit_meeting_info': 'Edit Meeting Info',
          'objective': 'Objective',
          'important_notes': 'Important Notes',

          // 分析面板
          'analysis_settings': 'Analysis Settings',
          'stance_analysis': 'Stance Analysis',
          'proposition_tracking': 'Proposition Tracking',

          // 对话项
          'speaker_label': 'Speaker',
          'play_audio': 'Play Audio',

          // 控制面板
          'recording_control': 'Recording Control',
          'resources': 'Resources',
          'background_docs': 'Background Documents',
          'reference_materials': 'Reference Materials',
          'documents': 'Documents',
          'manage_documents_desc': 'Manage reference documents',

          // 设置
          'settings': 'Settings',
          'language': 'Language',
          'server_settings': 'Server Settings',
          'socket_url': 'Socket URL',
          'socket_path': 'Socket Path',
          'enable_preview': 'Enable Preview',

          // 错误信息
          'update_failed': 'Failed to update meeting info',
          'recording_failed': 'Recording control failed: {}',
          'not_initialized': 'Not initialized',

          // 对话编辑
          'edit_conversation': 'Edit Conversation',
          'conversation_text': 'Content',
          'notes': 'Notes',
          'notes_hint': 'Add notes here...',

          // Stance Analysis
          'add_stance': 'Add Stance',
          'stance_name': 'Stance Name',
          'stance_description': 'Description',
          'add_participant': 'Add Participant',
          'add_new_user': 'Add New User',
          'add_user': 'Add User',
          'user_name': 'User Name',
          'confirm': 'Confirm',

          // Propositions
          'propositions': 'Propositions',
          'add_proposition': 'Add Proposition',
          'proposition_content': 'Content',
          'proposition_note': 'Note',
          'edit_stance': 'Edit Stance',
          'stance_evidence': 'Evidence',
          'stance_note': 'Analysis Note',
          'stance_type': 'Stance Type',
          'support': 'Support',
          'oppose': 'Oppose',
          'neutral': 'Neutral',
          'uncertain': 'Uncertain',

          // Stance Management
          'stance_management': 'Stance Management',
          'proposition_analysis': 'Proposition Analysis',
          'stance': 'Stance',

          'participants': 'Participants',
          'no_participants': 'No participants',
          'remove_from_stance': 'Remove from stance',

          'delete_stance': 'Delete stance',

          'no_stance': 'No Stance',
          'initial_stance': 'Initial Stance',

          'edit_proposition': 'Edit Proposition',
          'add_stance_opinion': 'Add Stance Opinion',
          'delete_proposition': 'Delete Proposition',
          'delete_proposition_confirm':
              'Are you sure you want to delete this proposition?',

          'no_stance_opinions': 'No stance opinions',

          'select_user': 'Select User',
          'current_user': 'Current User',
          'please_select_user': 'Please select a user',

          'stance_opinions': 'Stance Opinions',

          'select_speaker': 'Select Speaker',
          'current_speaker': 'Current Speaker',
          'bound_user': 'Bound User',
          'no_bound_user': 'No Bound User',
          'new_speaker': 'New Speaker',
          'speaker': 'Speaker',

          'summarize_conversation': 'Summarize',
          'start_recording': 'Start Recording',
          'stop_recording': 'Stop Recording',
          'meeting_history': 'Meeting History',

          'new_meeting': 'New Meeting',
          'no_meetings': 'No meetings yet',

          'server_address': 'Server Address',

          // Analysis
          'preview_prompt': 'Preview Prompt',
          'system_prompt': 'System Prompt',
          'user_prompt': 'User Prompt',
          'analyze_conversation': 'Analyze Conversation',
          'analysis_completed': 'Analysis completed',
          'analysis_failed': 'Failed to analyze conversation',
          'no_new_dialogs': 'No new dialogs to analyze',

          // Suggestions
          'generate_suggestions': 'Generate Suggestions',
          'suggestion_completed': 'Suggestions generated successfully',
          'suggestion_failed': 'Failed to generate suggestions',

          // Meeting management
          'clear_data': 'Clear Data',
          'clear_data_confirm':
              'Are you sure you want to clear all audio and conversation data for this meeting? This action cannot be undone.',
          'delete_meeting': 'Delete Meeting',
          'delete_meeting_confirm':
              'Are you sure you want to delete this meeting? This action will delete all related data and cannot be undone.',
          'export_audio': 'Export Audio',
          'audio_exported': 'Audio exported successfully',
          'export_text': 'Export Text',
          'text_exported': 'Text exported successfully',
          'text_export_preview': 'Text Export Preview',
          'copy': 'Copy',
          'open_folder': 'Open Folder',
          'copied_to_clipboard': 'Copied to clipboard',
          'open_storage_dir': 'Open Storage Directory',

          // 文档管理
          'upload_document': 'Upload Document',
          'document_preview': 'Document Preview',
          'document_summary': 'Document Summary',
          'view_summary': 'View Summary',
          'open_file_location': 'Open File Location',
          'cannot_open_file_location': 'Cannot open file location',
          'open_file_not_supported':
              'Opening files is not supported on this platform',
          'document_type': 'Document Type',
          'visibility': 'Visibility',
          'legal': 'Legal Document',
          'article': 'Article',
          'educational': 'Educational Material',
          'other': 'Other',
          'public': 'Public',
          'private': 'Private',
          'pending': 'Pending',
          'processing': 'Processing',
          'completed': 'Completed',
          'failed': 'Failed',
          'select_file': 'Select File',
          'please_select_file': 'Please select a file',
          'failed_to_pick_file': 'Failed to select file',
          'failed_to_upload': 'Failed to upload document',
          'error_uploading': 'Error occurred during upload',
          'uploading': 'Uploading...',
          'no_documents': 'No documents available',
          'document_deleted': 'Document deleted successfully',
          'failed_to_delete': 'Failed to delete document',
          'document_updated': 'Document updated successfully',
          'failed_to_update': 'Failed to update document',
          'failed_to_load_preview': 'Failed to load document preview',
          'delete_document_confirm':
              'Are you sure you want to delete "{title}"?',
          'no_structure_available': 'No document structure available',
          'sample_chunks': 'Sample Content',
          'edit_document': 'Edit Document',
          'upload': 'Upload',
          'view_document': 'View Document',
          'cannot_open_file': 'Cannot open file in browser',
        },
        'zh_CN': {
          // 应用标题
          'app_title': '智能会议助手',

          // 通用
          'error': '错误',
          'save': '保存',
          'cancel': '取消',
          'success': '成功',
          'settings_saved': '设置已保存',
          'settings_save_failed': '设置保存失败',
          'refresh': '刷新',
          'close': '关闭',
          'delete': '删除',
          'edit': '编辑',
          'preview': '预览',
          'title': '标题',
          'description': '描述',
          'status': '状态',
          'untitled': '未命名',
          'unknown': '未知',
          'confirm_delete': '确认删除',

          // 会议信息
          'meeting_info': '会议信息',
          'meeting_title': '会议标题',
          'meeting_title_hint': '输入会议标题',
          'meeting_objective': '核心目标',
          'meeting_objective_hint': '描述会议的核心目标',
          'meeting_notes': '重要说明',
          'meeting_notes_hint': '时间限制、特殊要求等',
          'untitled_meeting': '未命名会议',
          'edit_meeting_info': '编辑会议信息',
          'objective': '目标',
          'important_notes': '重要说明',

          // 分析面板
          'analysis_settings': '分析设置',
          'stance_analysis': '立场分析',
          'proposition_tracking': '主张跟踪',

          // 对话项
          'speaker_label': '说话人',
          'play_audio': '播放音频',

          // 控制面板
          'recording_control': '录音控制',
          'resources': '相关资料',
          'background_docs': '背景文档',
          'reference_materials': '参考资料',
          'documents': '文档管理',
          'manage_documents_desc': '管理参考文档资料',

          // 设置
          'settings': '设置',
          'language': '语言',
          'server_settings': '服务器设置',
          'socket_url': '服务器地址',
          'socket_path': '服务器路径',
          'enable_preview': '启用预览',

          // 错误信息
          'update_failed': '更新会议信息失败',
          'recording_failed': '录音控制失败: {}',
          'not_initialized': '未初始化',

          // 对话编辑
          'edit_conversation': '编辑对话',
          'conversation_text': '内容',
          'notes': '备注',
          'notes_hint': '在此添加备注...',

          // 派别分析相关
          'add_stance': '添加派别',
          'stance_name': '派别名称',
          'stance_description': '派别描述',
          'add_participant': '添加成员',
          'add_new_user': '添加新用户',
          'add_user': '添加用户',
          'user_name': '用户名称',
          'confirm': '确认',

          // 主张相关
          'propositions': '主张列表',
          'add_proposition': '添加主张',
          'proposition_content': '主张内容',
          'proposition_note': '备注说明',
          'edit_stance': '编辑立场',
          'stance_evidence': '支持证据',
          'stance_note': '分析备注',
          'stance_type': '立场类型',
          'support': '支持',
          'oppose': '反对',
          'neutral': '中立',
          'uncertain': '不确定',

          // Stance Management
          'stance_management': '派别管理',
          'proposition_analysis': '立场主张分析',
          'stance': '所属派别',

          'participants': '成员列表',
          'no_participants': '暂无成员',
          'remove_from_stance': '移出派别',

          'delete_stance': '删除派别',

          'no_stance': '暂不分配派别',
          'initial_stance': '初始派别',

          'edit_proposition': '编辑主张',
          'add_stance_opinion': '添加立场观点',
          'delete_proposition': '删除主张',
          'delete_proposition_confirm': '确定要删除这个主张吗？',

          'no_stance_opinions': '暂无立场观点',

          'select_user': '选择用户',
          'current_user': '当前用户',
          'please_select_user': '请选择用户',

          'stance_opinions': '立场观点',

          'select_speaker': '选择说话人',
          'current_speaker': '当前说话人',
          'bound_user': '绑定用户',
          'no_bound_user': '未绑定用户',
          'new_speaker': '新建说话人',
          'speaker': '说话人',

          'summarize_conversation': '总结对话',
          'generate_suggestions': '生成建议',
          'start_recording': '开始录音',
          'stop_recording': '停止录音',
          'meeting_history': '历史会议',

          'new_meeting': '新建会议',
          'no_meetings': '暂无会议',

          'server_address': '服务器地址',

          // Analysis
          'preview_prompt': '预览提示词',
          'system_prompt': '系统提示词',
          'user_prompt': '用户提示词',
          'analyze_conversation': '分析对话',
          'analysis_completed': '分析完成',
          'analysis_failed': '分析对话失败',
          'no_new_dialogs': '没有新的对话需要分析',

          // Suggestions
          'suggestion_completed': '建议生成完成',
          'suggestion_failed': '生成建议失败',

          // Meeting management
          'clear_data': '清除数据',
          'clear_data_confirm': '确定要清除该会议的所有音频和对话记录吗？此操作不可恢复。',
          'delete_meeting': '删除会议',
          'delete_meeting_confirm': '确定要删除该会议吗？此操作将删除所有相关数据且不可恢复。',
          'export_audio': '导出音频',
          'audio_exported': '音频导出成功',
          'export_text': '导出文本',
          'text_exported': '文本导出成功',
          'text_export_preview': '文本导出预览',
          'copy': '复制',
          'open_folder': '打开文件夹',
          'copied_to_clipboard': '已复制到剪贴板',
          'open_storage_dir': '打开存储目录',

          // 文档管理
          'upload_document': '上传文档',
          'document_preview': '文档预览',
          'document_summary': '文档摘要',
          'view_summary': '查看摘要',
          'open_file_location': '打开文件位置',
          'cannot_open_file_location': '无法打开文件位置',
          'open_file_not_supported': '此平台不支持打开文件',
          'document_type': '文档类型',
          'visibility': '可见性',
          'legal': '法律文档',
          'article': '文章',
          'educational': '教育资料',
          'other': '其他',
          'public': '公开',
          'private': '私有',
          'pending': '等待处理',
          'processing': '处理中',
          'completed': '已完成',
          'failed': '失败',
          'select_file': '选择文件',
          'please_select_file': '请选择文件',
          'failed_to_pick_file': '选择文件失败',
          'failed_to_upload': '上传文档失败',
          'error_uploading': '上传过程中发生错误',
          'uploading': '上传中...',
          'no_documents': '暂无文档',
          'document_deleted': '文档删除成功',
          'failed_to_delete': '删除文档失败',
          'document_updated': '文档更新成功',
          'failed_to_update': '更新文档失败',
          'failed_to_load_preview': '加载文档预览失败',
          'delete_document_confirm': '确定要删除"{title}"吗？',
          'no_structure_available': '暂无文档结构',
          'sample_chunks': '示例内容',
          'edit_document': '编辑文档',
          'upload': '上传',
          'view_document': '查看文档',
          'cannot_open_file': '无法在浏览器中打开文件',
        },
      };
}
