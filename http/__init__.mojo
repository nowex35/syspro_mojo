from .response import *
from .request import *


trait Encodable:
    fn encode(owned self) -> Bytes:
        ...


@always_inline
fn encode[T: Encodable](owned data: T) -> Bytes:
    return data^.encode()
