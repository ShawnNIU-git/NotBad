"""按 token 统计每日调用次数。先放内存里，重启清零；正式上线换成 Redis 或数据库。"""

from __future__ import annotations

import threading
from datetime import date
from typing import Callable


class DailyQuota:
    def __init__(self, limit: int, today: Callable[[], date] = date.today):
        self.limit = limit
        self._today = today
        self._used: dict[tuple[str, date], int] = {}
        self._lock = threading.Lock()

    def used(self, token: str) -> int:
        with self._lock:
            return self._used.get((token, self._today()), 0)

    def remaining(self, token: str) -> int:
        return max(0, self.limit - self.used(token))

    def try_consume(self, token: str) -> bool:
        """额度够就记一次并返回 True，否则返回 False。"""
        with self._lock:
            key = (token, self._today())
            # 顺手清掉过期的记录，避免内存一直涨
            for old in [k for k in self._used if k[1] != key[1]]:
                del self._used[old]
            if self._used.get(key, 0) >= self.limit:
                return False
            self._used[key] = self._used.get(key, 0) + 1
            return True

    def refund(self, token: str) -> None:
        """上游调用失败时退回额度。"""
        with self._lock:
            key = (token, self._today())
            if self._used.get(key, 0) > 0:
                self._used[key] -= 1
