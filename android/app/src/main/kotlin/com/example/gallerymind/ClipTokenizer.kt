package com.example.gallerymind

// Minimal CLIP byte-pair tokenizer. It turns human text into the integer token
// IDs expected by textual_quant.onnx.
class ClipTokenizer(
    private val encoder: Map<String, Int>,
    private val bpeRanks: Map<Pair<String, String>, Int>,
) {
    private val encodeRegex =
        Regex("""<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+""")
    private val byteEncoder = buildByteEncoder()

    fun encode(text: String): MutableList<Int> {
        // Split text into CLIP-style pieces, byte-encode each piece, then apply
        // BPE merges and map final tokens to vocab IDs.
        val tokens = encodeRegex.findAll(text).map { result ->
            result.value.codePoints().boxed().map { byteEncoder[it]!! }.toArray().joinToString("")
        }
        return tokens.flatMap { bpe(it) }.map { encoder[it]!! }.toMutableList()
    }

    private fun bpe(token: String): List<String> {
        // Byte-pair encoding repeatedly merges the highest-priority adjacent
        // token pair until no trained merge rule applies.
        if (token.length <= 1) return listOf("$token ")

        val wordWithBreak = token.map { it.toString() }.toMutableList()
        wordWithBreak[wordWithBreak.size - 1] = "${wordWithBreak[wordWithBreak.size - 1]} "
        var word = wordWithBreak.toList()
        var pairs = getPairs(word)

        while (true) {
            if (!pairs.any { bpeRanks.containsKey(it) }) break
            val (first, second) = pairs.minBy { bpeRanks.getOrDefault(it, Int.MAX_VALUE) }

            var i = 0
            val newWord = mutableListOf<String>()
            while (i < word.size) {
                val j = word.withIndex().indexOfFirst { it.index >= i && it.value == first }
                if (j != -1) {
                    newWord.addAll(word.subList(i, j))
                    i = j
                } else {
                    newWord.addAll(word.subList(i, word.size))
                    break
                }

                if (word[i] == first && i < word.size - 1 && word[i + 1] == second) {
                    newWord.add(first + second)
                    i += 2
                } else {
                    newWord.add(word[i])
                    i += 1
                }
            }

            word = newWord
            if (word.size == 1) break
            pairs = getPairs(word)
        }

        return word
    }

    private fun getPairs(word: List<String>): Set<Pair<String, String>> {
        // Return all adjacent pairs in the current token list so BPE can choose
        // the next merge.
        return mutableSetOf<Pair<String, String>>().apply {
            for (i in 0 until word.size - 1) {
                add(word[i] to word[i + 1])
            }
        }
    }

    private fun buildByteEncoder(): Map<Int, String> {
        // CLIP maps every possible byte to a visible unicode string before BPE,
        // avoiding unknown tokens for unusual characters.
        val bytes = mutableListOf<Int>()
        bytes.addAll(33..126)
        bytes.addAll(161..172)
        bytes.addAll(174..255)

        val chars = bytes.toMutableList()
        var next = 0
        for (byte in 0..255) {
            if (!bytes.contains(byte)) {
                bytes.add(byte)
                chars.add(256 + next)
                next += 1
            }
        }

        return bytes.indices.associate { index -> bytes[index] to chars[index].toChar().toString() }
    }
}
