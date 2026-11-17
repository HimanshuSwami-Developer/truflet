"""The payments service's public interface — the only module other apps import.

    from payments import service as payments
    result = payments.charge(user_id, 1647, "upi", reference="TRF-17N26-7041", upi_id="me@bank")
    if not result.success: ...

Everything crosses this boundary as plain values, never model instances, so the implementation can
move behind HTTP or a message queue later: write a class with the same methods as `PaymentService`
(e.g. one that calls the new service) and point `PAYMENT_SERVICE` in settings at it.

The wallet ("Turflet balance") belongs to this service: no other code changes `wallet_balance`.
It still lives on the user row today; when payments moves out it becomes this service's own ledger.
"""
from importlib import import_module
from typing import Protocol

from django.conf import settings
from django.db.models import F

from .gateways import ChargeResult, get_gateway, make_txn_id

WALLET = "wallet"


class PaymentService(Protocol):
    def charge(self, user_id: int, amount: int, method: str, reference: str, upi_id: str = "") -> ChargeResult:
        """Takes `amount` from the player: from their wallet when method is "wallet", otherwise through
        the gateway. Never raises for a declined payment — check `result.success` / `result.message`."""

    def refund(self, user_id: int | None, amount: int, method: str, transaction_id: str) -> bool:
        """Gives `amount` back the way it was paid (wallet → wallet, otherwise through the gateway)."""

    def wallet_balance(self, user_id: int) -> int: ...

    def credit_wallet(self, user_id: int, amount: int) -> None:
        """Adds money to a player's wallet (refunds, recovered match shares, admin top-ups)."""

    def debit_wallet(self, user_id: int, amount: int) -> bool:
        """Takes money from a wallet only if the full amount is there. Returns whether it did."""

    def adjust_wallet(self, user_id: int, delta: int) -> int:
        """Admin correction: adds `delta` (may be negative, never going below zero). Returns the balance."""


def _users():
    from django.contrib.auth import get_user_model

    return get_user_model().objects


class LocalPaymentService:
    """In-process implementation: gateway calls plus the wallet column on the user row."""

    def charge(self, user_id, amount, method, reference, upi_id=""):
        if amount <= 0:
            return ChargeResult(True, transaction_id=make_txn_id(method))
        if method == "upi" and upi_id and "@" not in upi_id:
            return ChargeResult(False, message="Enter a valid UPI ID, e.g. yourname@bank")
        if method == WALLET:
            if not self.debit_wallet(user_id, amount):
                return ChargeResult(False, message="Not enough Turflet balance.")
            return ChargeResult(True, transaction_id=make_txn_id(WALLET))
        return get_gateway().charge(amount, method, reference, upi_id)

    def refund(self, user_id, amount, method, transaction_id):
        if amount <= 0:
            return True
        if method == WALLET:
            if user_id:
                self.credit_wallet(user_id, amount)
            return True
        return get_gateway().refund(amount, transaction_id)

    def wallet_balance(self, user_id):
        return _users().filter(pk=user_id).values_list("wallet_balance", flat=True).first() or 0

    def credit_wallet(self, user_id, amount):
        if amount > 0:
            _users().filter(pk=user_id).update(wallet_balance=F("wallet_balance") + amount)

    def debit_wallet(self, user_id, amount):
        if amount <= 0:
            return True
        # one conditional UPDATE: safe against two payments racing for the same balance
        return bool(_users().filter(pk=user_id, wallet_balance__gte=amount)
                    .update(wallet_balance=F("wallet_balance") - amount))

    def adjust_wallet(self, user_id, delta):
        if delta > 0:
            self.credit_wallet(user_id, delta)
        elif delta < 0:
            balance = self.wallet_balance(user_id)
            self.debit_wallet(user_id, min(balance, -delta))
        return self.wallet_balance(user_id)


_service = None


def get_service() -> PaymentService:
    """The configured implementation (`PAYMENT_SERVICE` = dotted path to a class)."""
    global _service
    if _service is None:
        path = getattr(settings, "PAYMENT_SERVICE", "payments.service.LocalPaymentService")
        module, _, name = path.rpartition(".")
        _service = getattr(import_module(module), name)()
    return _service


# Module-level shortcuts, so call sites read `payments.charge(...)`.
def charge(user_id, amount, method, reference, upi_id=""):
    return get_service().charge(user_id, amount, method, reference, upi_id)


def refund(user_id, amount, method, transaction_id):
    return get_service().refund(user_id, amount, method, transaction_id)


def wallet_balance(user_id):
    return get_service().wallet_balance(user_id)


def credit_wallet(user_id, amount):
    return get_service().credit_wallet(user_id, amount)


def debit_wallet(user_id, amount):
    return get_service().debit_wallet(user_id, amount)


def adjust_wallet(user_id, delta):
    return get_service().adjust_wallet(user_id, delta)
