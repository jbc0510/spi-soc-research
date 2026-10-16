import unittest

from scripts.task2g_compare_xilinx_bit_payload import extract_payload, reverse_word_bytes


def make_bit(payload):
    header = b"\x00\x09" + b"012345678" + b"\x00\x01"
    fields = b"".join(bytes([tag]) + len(value).to_bytes(2, "big") + value for tag, value in zip(b"abcd", (b"a", b"b", b"c", b"d")))
    return header + fields + b"e" + len(payload).to_bytes(4, "big") + payload


class XilinxBitPayloadTests(unittest.TestCase):
    def test_extracts_payload_after_metadata(self):
        self.assertEqual(b"\x01\x02\x03\x04", extract_payload(make_bit(b"\x01\x02\x03\x04")))

    def test_rejects_payload_length_mismatch(self):
        data = make_bit(b"\x01\x02\x03\x04")[:-1]
        with self.assertRaises(ValueError):
            extract_payload(data)

    def test_reverses_each_32_bit_word(self):
        self.assertEqual(b"\x04\x03\x02\x01\x08\x07\x06\x05", reverse_word_bytes(b"\x01\x02\x03\x04\x05\x06\x07\x08"))


if __name__ == "__main__":
    unittest.main()
