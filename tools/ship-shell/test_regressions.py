"""Bridge lifecycle and malformed-input regression tests (standard library)."""
import json
import socket
import struct
import threading
import unittest
from unittest.mock import patch
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location("bridge",Path(__file__).with_name("bridge.py"))
bridge=importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

class Clock:
    now=0
    def time(self): return self.now
class Conn:
    def __init__(self): self.messages=[];self.closed=False
    def sendall(self,data): self.messages.append(data)
    def shutdown(self,how): pass
    def close(self): self.closed=True
class Rcon:
    def __init__(self): self.commands=[]
    def send(self,command): self.commands.append(command)
class Tests(unittest.TestCase):
    def setUp(self):
        self.clock=Clock();self.rcon=Rcon()
        self.bridge=bridge.Bridge({"token":"secret"},self.clock,self.rcon)
    def hello(self,conn,role="engine"):
        return self.bridge._hello(conn,{"type":"hello","id":12,"token":"secret","role":role})
    def test_lost_connection_preserves_watchdog(self):
        engine,watchdog=Conn(),Conn()
        self.hello(watchdog,"watchdog");self.hello(engine)
        before=len(watchdog.messages)
        self.bridge._detach(engine)
        self.assertTrue(self.bridge.armed)
        self.assertEqual(len(watchdog.messages),before)
    def test_replacement_resets_busy_and_ignores_stale_status(self):
        old,new=Conn(),Conn();self.hello(old)
        self.bridge.eval_id="stuck";self.bridge.eval_sent_at=0;self.bridge.shutdown_sent=True
        self.hello(new)
        self.assertTrue(old.closed)
        self.assertIsNone(self.bridge.eval_id)
        self.assertFalse(self.bridge.shutdown_sent)
        self.bridge._on_engine({"type":"status","y":123},old)
        self.assertIsNone(self.bridge.status)
        self.bridge._detach(old)
        self.assertIs(self.bridge.engine_conn,new)
    def test_repeated_shutdown_cycles(self):
        self.hello(Conn())
        for cycle in range(2):
            self.bridge.eval_sent_at=self.clock.now
            self.bridge.frame_after_eval=False
            self.bridge.shutdown_sent=False
            self.clock.now+=11
            self.bridge._scan()
            self.bridge._scan()
        self.assertEqual(len(self.rcon.commands),2)
    def test_send_failure_cleans_request(self):
        class Broken(Conn):
            def sendall(self,data): raise OSError("gone")
        self.bridge.engine_conn=Broken()
        result=self.bridge._request({"type":"eval","code":"return 1"},1)
        self.assertFalse(result["ok"])
        self.assertEqual(self.bridge.waiters,{})
        self.assertIsNone(self.bridge.eval_id)
    def test_encoded_size_includes_json_escaping(self):
        with self.assertRaises(ValueError):
            self.bridge._send_json(Conn(),{"content":'"'*bridge.FRAME_LIMIT})
    def test_http_rejects_invalid_bodies(self):
        server=bridge.ThreadingHTTPServer(("127.0.0.1",0),self.bridge._http_handler())
        worker=threading.Thread(target=server.serve_forever,daemon=True);worker.start()
        try:
            import http.client
            for body in ("[]","null","1","{"):
                conn=http.client.HTTPConnection(*server.server_address,timeout=2)
                conn.request("POST","/eval",body,{"Content-Type":"application/json"})
                response=conn.getresponse()
                self.assertEqual(response.status,400);response.read();conn.close()
        finally: server.shutdown();server.server_close();worker.join()
    def test_huge_frame_header_is_rejected_without_payload(self):
        left,right=socket.socketpair()
        try:
            left.sendall(b"\x81\xff"+(2**40).to_bytes(8,"big")+b"mask")
            self.assertEqual(bridge.read_frame(right),("too_large",b""))
        finally: left.close();right.close()
    def test_rcon_rejects_negative_length(self):
        rcon=bridge.MinecraftRcon("localhost",1,"secret")
        with patch.object(rcon,"_exact",return_value=struct.pack("<i",-1)):
            with self.assertRaises(ConnectionError): rcon._read_packet(None)

if __name__=="__main__": unittest.main()
