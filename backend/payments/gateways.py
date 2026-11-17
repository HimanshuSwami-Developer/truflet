"""Payment gateways (the external processor behind cards, UPI and net banking).

`mock` confirms instantly so the full app flow works in development. To go live, add a gateway
(e.g. Razorpay: create an order, verify the signature in `charge`) to GATEWAYS and set
PAYMENT_PROVIDER in the environment. The wallet never goes through a gateway — see service.py.
"""
import secrets
from dataclasses import dataclass

from django.conf import settings


@dataclass
class ChargeResult:
    success: bool
    transaction_id: str = ""
    message: str = ""


def make_txn_id(method):
    return f"{method.upper()}/{secrets.randbelow(10000):04d}/{secrets.randbelow(10000):04d}/{secrets.randbelow(10000):04d}"


class MockGateway:
    name = "mock"

    def charge(self, amount, method, reference, upi_id=""):
        return ChargeResult(True, transaction_id=make_txn_id(method))

    def refund(self, amount, transaction_id):
        return True


GATEWAYS = {"mock": MockGateway}


def get_gateway():
    return GATEWAYS.get(settings.PAYMENT_PROVIDER, MockGateway)()
