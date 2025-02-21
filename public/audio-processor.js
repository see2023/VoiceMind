class AudioProcessor extends AudioWorkletProcessor {
	constructor() {
		super();
		this.bufferSize = 16000 * 0.1; // 100ms at 16kHz
		this.buffer = new Float32Array(this.bufferSize);
		this.writeIndex = 0;
	}

	process(inputs, outputs, parameters) {
		const input = inputs[0][0];
		if (!input) return true;

		// 将新的音频数据写入缓冲区
		for (let i = 0; i < input.length; i++) {
			this.buffer[this.writeIndex] = input[i];
			this.writeIndex++;

			// 当缓冲区满时，发送数据并重置
			if (this.writeIndex >= this.bufferSize) {
				this.port.postMessage(Array.from(this.buffer));
				this.writeIndex = 0;
			}
		}

		return true;
	}
}

registerProcessor('audio-processor', AudioProcessor); 