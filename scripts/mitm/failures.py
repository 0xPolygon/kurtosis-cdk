import json
from time import sleep
from random import randint
from mitmproxy import http  # noqa
from mitmproxy.script import concurrent  # noqa


class GenericFailure:
    def __init__(self, ratio, selected_peers=[]):
        self.ratio = ratio
        self.peers = selected_peers

    def _eligible_peer(self, flow):
        _peer = flow.client_conn.peername
        _peer_addr = _peer[0] if _peer else None
        return (not self.peers) or (_peer_addr in self.peers)

    def _random_select(self):
        assert (0.0 <= self.ratio <= 1.0)
        a = int(self.ratio * 100)
        b = randint(0, 99)

        if a > b:
            return True
        else:
            return False

    def _set_my_header(self, flow):
        flow.response.headers["mitm"] = "Intercepted"


class GenericResponseFailure(GenericFailure):
    def _my_response(self, flow):
        pass

    def _eligible_response(self, flow):
        return True

    @concurrent
    def response(self, flow):
        if not self._eligible_response(flow):
            return

        if not self._eligible_peer(flow):
            return

        if not self._random_select():
            return

        self._set_my_header(flow)
        self._my_response(flow)


class GenericRequestFailure(GenericFailure):
    def _my_request(self, flow):
        pass

    def _eligible_request(self, flow):
        return True

    @concurrent
    def request(self, flow):
        if not self._eligible_request(flow):
            return

        if not self._eligible_peer(flow):
            return

        if not self._random_select():
            return

        self._my_request(flow)


# Error classes

class HttpErrorResponse(GenericRequestFailure):
    DEFAULT_ERROR_CODES = [401, 403, 404, 405, 429, 500, 502, 503, 504]

    def __init__(
        self, ratio, selected_peers=[], error_codes=DEFAULT_ERROR_CODES
    ):
        self.error_codes = error_codes
        super().__init__(ratio, selected_peers)

    def _my_request(self, flow):
        error_code = self.error_codes[randint(0, len(self.error_codes) - 1)]
        flow.response = \
            http.Response.make(
                error_code,
                f"HTTP Error {error_code}",
                {"Content-Type": "text/plain"}
            )


class NullResponse(GenericRequestFailure):
    def _my_request(self, flow):
        flow.response = http.Response.make(200, "", {})
        self._set_my_header(flow)


class EmptyJSONResultResponse(GenericRequestFailure):
    def _my_request(self, flow):
        body = json.dumps({"result": None})
        flow.response = \
            http.Response.make(200, body, {"Content-Type": "application/json"})


class EmptyJSONResponse(GenericRequestFailure):
    def _my_request(self, flow):
        body = json.dumps({})
        flow.response = \
            http.Response.make(200, body, {"Content-Type": "application/json"})


class ArbitraryHTMLResponse(GenericRequestFailure):
    def _my_request(self, flow):
        flow.response = \
            http.Response.make(
                200,
                "<html><body>Random HTML</body></html>",
                {"Content-Type": "text/html"}
            )


class ArbitraryJSONResponse(GenericRequestFailure):
    def _my_request(self, flow):
        flow.response = \
            http.Response.make(
                200,
                json.dumps({"result": "Random JSON"}),
                {"Content-Type": "application/json"}
            )


class SlowResponse(GenericResponseFailure):
    RANDOM_MIN_SECONDS = 1
    RANDOM_MAX_SECONDS = 5

    def _my_response(self, flow):
        sleep(
            randint(self.RANDOM_MIN_SECONDS, self.RANDOM_MAX_SECONDS)
        )


class CorruptedJSONResponse(GenericResponseFailure):
    def _eligible_response(self, flow):
        if flow.response.headers.get("Content-Type") == "application/json":
            if len(flow.response.text) < 2:
                return False
            try:
                body = json.loads(flow.response.text)
                return (isinstance(body, dict) and body.get("result"))
            except json.JSONDecodeError:
                return False
        else:
            return False

    def _my_response(self, flow):
        flow.response.text = \
            flow.response.text[:randint(0, len(flow.response.text) - 1)] \
            + "0" \
            + flow.response.text[randint(0, len(flow.response.text) - 1):]


class NoResponse(GenericRequestFailure):
    def _my_request(self, flow):
        flow.kill()


class AddJSONFieldsResponse(GenericResponseFailure):
    MIN_EXTRA_FIELDS = 1
    MAX_EXTRA_FIELDS = 5

    def _eligible_response(self, flow):
        if flow.response.headers.get("Content-Type") == "application/json":
            try:
                body = json.loads(flow.response.text)
                return (isinstance(body, dict) and body.get("result"))
            except json.JSONDecodeError:
                return False
        else:
            return False

    def _my_response(self, flow):
        body = json.loads(flow.response.text)
        for _ in range(randint(self.MIN_EXTRA_FIELDS, self.MAX_EXTRA_FIELDS)):
            if isinstance(body["result"], dict):
                body["result"][f"new_field_{_}"] = f"new_value_{_}"
            elif isinstance(body["result"], list):
                body["result"].append({f"new_value_{_}": f"new_value_{_}"})
        flow.response.text = json.dumps(body)


class RedirectRequest(GenericRequestFailure):
    def __init__(self, ratio, selected_peers=[], redirect_url=None):
        self.scheme = redirect_url.split("://")[0]
        self.host = redirect_url.split("://")[1].split(":")[0]
        self.port = int(redirect_url.split(":")[2])
        super().__init__(ratio, selected_peers)

    def _my_request(self, flow):
        flow.request.scheme = self.scheme
        flow.request.host = self.host
        flow.request.port = self.port
        flow.request.headers["Host"] = self.host


class InvalidJSONResponse(GenericRequestFailure):
    def _my_request(self, flow):
        flow.response = \
            http.Response.make(
                200,
                '{"result": This is a invalid JSOM}',
                {"Content-Type": "application/json"}
            )


class RemoveJSONFieldsResponse(GenericResponseFailure):
    MIN_REMOVED_FIELDS = 1
    MAX_REMOVED_FIELDS = 3

    def _eligible_response(self, flow):
        if flow.response.headers.get("Content-Type") == "application/json":
            try:
                body = json.loads(flow.response.text)
                return (
                    isinstance(body, dict) and
                    body.get("result") and
                    isinstance(body["result"], dict) and
                    (len(body["result"]) >= self.MAX_REMOVED_FIELDS)
                )
            except json.JSONDecodeError:
                return False
        else:
            return False

    def _my_response(self, flow):
        body = json.loads(flow.response.text)
        for _ in range(
            randint(self.MIN_REMOVED_FIELDS, self.MAX_REMOVED_FIELDS)
        ):
            key = list(body["result"].keys())[
                randint(0, len(body["result"]) - 1)
            ]
            del body["result"][key]

        flow.response.text = json.dumps(body)


class WrongContentTypeResponse(GenericResponseFailure):
    def _eligible_response(self, flow):
        return \
            (flow.response.headers.get("Content-Type") == "application/json")

    def _my_response(self, flow):
        flow.response.headers["Content-Type"] = "application/pdf"


class WrongContentLengthResponse(GenericResponseFailure):
    def _my_response(self, flow):
        if flow.response.headers.get("Content-Length", 0) % 2 == 0:
            flow.response.headers["Content-Length"] = "0"
        else:
            flow.response.headers["Content-Length"] = "1099511627776"


# class OlderLatestBlock(GenericResponseFailure, GenericRequestFailure):
#     BLOCK_DIFF = 20

#     def __init__(self, ratio):
#         self.fids = []
#         super().__init__(ratio)

#     def _eligible_request(self, flow):
#         content = json.loads(flow.request.content)
#         print(f"Content: {content}")
#         eligible = (
#             (flow.request.headers.get("Content-Type") == "application/json")
#             and isinstance(content, dict)
#             and (
#                 content.get("method") == "eth_blockNumber"
#                 or (
#                     content.get("method") == "eth_getBlockByNumber"
#                     and any(
#                         x in content.get("params", [])
#                         for x in ["finalized", "safe", "latest"]
#                     )
#                 )
#             )
#         )
#         print(f"Eligible request: {eligible}")
#         return eligible

#     def _my_request(self, flow):
#         content = json.loads(flow.request.content)
#         if content.get("method") == "eth_getBlockByNumber":
#             # let's query the server here
            
#         else:
#             self.fids.append(flow.id)

#     def _eligible_response(self, flow):
#         return flow.id in self.fids

#     def _my_response(self, flow):
#         self.fids.remove(flow.id)
#         body = json.loads(flow.response.text)
#         print(f"Old block: {body['result']}")
#         body["result"] = hex(int(body["result"], 16) - self.BLOCK_DIFF)
#         print(f"New block: {body['result']}")
#         flow.response.text = json.dumps(body)
