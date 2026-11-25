"""Offline protocol tests (no hardware or pyserial required)."""
import pathlib
import sys
import unittest

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1] / "host"))
from npu_serial import (
    BIAS, CONFIGURE, INFER, PING, WEIGHT, NpuBoard,
    ProtocolError, decode_reply, pack_request
)


class MockSerial:
    def __init__(self):
        self.requests = []
        self.reply = b""
    def write(self, packet):
        assert packet[0] == 0xA5
        verify = 0
        for x in packet[1:-1]:
            verify ^= x
        assert verify == packet[-1]
        cmd = packet[1]
        self.requests.append(packet)
        scores = [20, 30] + [0]*6 if cmd == INFER else [0]*8
        fields = bytes([cmd, 0, 1 if cmd == INFER else 0] + scores)
        checksum = 0
        for x in fields:
            checksum ^= x
        self.reply = bytes([0x5A]) + fields + bytes([checksum])
        return len(packet)
    def flush(self):
        pass
    def read(self,count):
        assert count == 13
        return self.reply
    def close(self):
        pass


class TransportTest(unittest.TestCase):
    def test_packets_and_decode(self):
        io=MockSerial()
        fpga=NpuBoard(io)
        fpga.ping()
        fpga.write_weight(4095,-128)
        fpga.write_bias(127,-123456)
        fpga.configure(8,(16,8,2),shift=4)
        result=fpga.infer([10]*8)
        self.assertEqual((result.class_index,result.scores[:2]),(1,(20,30)))
        self.assertEqual([p[1] for p in io.requests],
                         [PING,WEIGHT,BIAS,CONFIGURE,INFER])
        self.assertEqual(len(io.requests[-1]),35)
        self.assertEqual(io.requests[1][2:5],bytes([255,15,128]))
        self.assertEqual(io.requests[2][2:7], bytes([127]) + (-123456).to_bytes(4,"little",signed=True))

    def test_bad_checksum_rejected(self):
        raw=bytes([0x5A, PING, 0, 0]+[0]*8+[0])
        with self.assertRaises(ProtocolError):
            decode_reply(raw,PING)

    def test_program_model_size(self):
        io=MockSerial()
        board=NpuBoard(io)
        board.load_demo_model(8,(16,8,2))
        weights=[x for x in io.requests if x[1]==WEIGHT]
        biases=[x for x in io.requests if x[1]==BIAS]
        self.assertEqual(len(weights),272)
        self.assertEqual(len(biases),26)
        self.assertEqual(io.requests[-1][1],CONFIGURE)

    def test_input_bounds(self):
        with self.assertRaises(ValueError):
            NpuBoard(MockSerial()).infer([128])


if __name__=="__main__":
    unittest.main()
