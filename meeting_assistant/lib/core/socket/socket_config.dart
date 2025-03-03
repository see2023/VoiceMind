class SocketConfig {
  static String baseUrl = 'localhost:9000'; // 只存储主机和端口

  // HTTP URL
  static String get serverUrl => 'http://$baseUrl';

  // WebSocket URL
  static String get wsUrl => 'ws://$baseUrl/ws/socket.io';

  // API URL
  static String get apiUrl => 'http://$baseUrl/api';

  // Socket.IO 配置
  static Map<String, dynamic> get socketOptions => {
        'transports': ['websocket'],
        'path': '/ws/socket.io',
      };
}
