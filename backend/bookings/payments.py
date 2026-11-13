"""Payment provider abstraction.

`mock` confirms instantly so the full app flow works in development.
To go live, implement a provider (e.g. Razorpay: create an order on hold, verify the
signature in `charge`) and set PAYMENT_PROVIDER in the environment.
"""
from dataclasses import dataclass

from django.conf import settings

from .models import make_txn_id


@dataclass
class ChargeResult:
    success: bool
    transaction_id: str = ""
    message: str = ""


class MockProvider:
    name = "mock"

    def charge(self, booking, method, upi_id=""):
        if method == "upi" and upi_id and "@" not in upi_id:
            return ChargeResult(False, message="Enter a valid UPI ID, e.g. yourname@bank")
        return ChargeResult(True, transaction_id=make_txn_id(method))

    def charge_amount(self, amount, method, reference):
        return ChargeResult(True, transaction_id=make_txn_id(method))

    def refund(self, booking, amount):
        return True

    def refund_amount(self, amount, transaction_id):
        """Refunds part of a split payment (a player's share)."""
        return True


PROVIDERS = {"mock": MockProvider}


def get_provider():
    return PROVIDERS.get(settings.PAYMENT_PROVIDER, MockProvider)()
