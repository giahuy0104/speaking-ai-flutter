package com.innotrik.aispeaking

/**
 * Chọn mức âm lượng cho một clip dựng sẵn.
 *
 * `assets/data/audio_loudness.json` đã đo sẵn gain của mọi clip đóng gói lúc
 * build, và cả hai nền tảng tra cùng bảng đó. Trước đây Android vẫn giải mã lại
 * clip trong nền rồi cho số đo runtime **đè lên** số của manifest, nên từ lần
 * phát thứ hai trở đi cùng một clip lại vang lên ở một mức khác — đúng thứ
 * manifest sinh ra để loại bỏ.
 *
 * Clip không có trong manifest — tiếng tổng hợp, clip tải về — vẫn phải đo.
 */
object AuthoredPromptLevel {
    /** Dùng khi không bên nào đưa ra được con số. */
    const val DEFAULT_GAIN_DB = 8.0

    /**
     * Gain để phát, tính theo dB.
     *
     * Manifest thắng: nó là số đo lúc build của đúng clip này, không phụ thuộc
     * codec của máy và giống hệt nhau ở mọi lần phát.
     */
    fun gainDb(
        manifestGainDb: Double?,
        measuredGainDb: Double?,
        fallbackGainDb: Double = DEFAULT_GAIN_DB,
    ): Double = manifestGainDb ?: measuredGainDb ?: fallbackGainDb

    /** Chỉ giải mã clip khi manifest không phủ nó. */
    fun shouldMeasure(manifestGainDb: Double?): Boolean = manifestGainDb == null
}
