"""Payments service: charges, refunds and the Turflet wallet.

Other apps talk to it only through `payments.service` with plain values (user ids, amounts,
transaction ids). It is the only code that changes a wallet balance. That keeps the boundary
clean enough to run payments as its own microservice later.
"""
