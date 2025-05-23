from syspro_http.http import HTTPResponse

alias TODO_MESSAGE = "TODO".as_bytes()


@value
struct ErrorHandler:
    fn Error(self) -> HTTPResponse:
        return HTTPResponse(TODO_MESSAGE)
