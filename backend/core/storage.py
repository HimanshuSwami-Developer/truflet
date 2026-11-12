"""Django storage backend that stores media on Cloudinary.

Enabled automatically when CLOUDINARY_URL is set (see settings.STORAGES).
The stored file "name" is the Cloudinary public_id plus extension, so URLs are
built without any network call.
"""
import os
import uuid

import cloudinary
import cloudinary.uploader
import cloudinary.utils
from django.conf import settings
from django.core.files.storage import Storage
from django.utils.deconstruct import deconstructible


@deconstructible
class CloudinaryMediaStorage(Storage):
    def __init__(self, folder=None):
        self.folder = folder or getattr(settings, "CLOUDINARY_FOLDER", "turflet")
        cloudinary.config(secure=True)  # reads CLOUDINARY_URL from the environment

    def _public_id(self, name):
        base, _ext = os.path.splitext(name)
        return base

    def _save(self, name, content):
        base, ext = os.path.splitext(name)
        public_id = f"{self.folder}/{base}-{uuid.uuid4().hex[:8]}"
        content.seek(0)
        result = cloudinary.uploader.upload(
            content, public_id=public_id, resource_type="image", overwrite=False,
        )
        return f"{result['public_id']}.{result.get('format', ext.lstrip('.') or 'jpg')}"

    def _open(self, name, mode="rb"):
        raise NotImplementedError("Cloudinary files are served by URL; open() is not supported.")

    def delete(self, name):
        if name:
            cloudinary.uploader.destroy(self._public_id(name), resource_type="image")

    def exists(self, name):
        return False  # public ids get a random suffix, so names never clash

    def size(self, name):
        return 0

    def url(self, name):
        if not name:
            return ""
        public_id, ext = os.path.splitext(name)
        url, _ = cloudinary.utils.cloudinary_url(
            public_id, format=ext.lstrip(".") or None, secure=True,
            fetch_format="auto", quality="auto",
        )
        return url

    def get_available_name(self, name, max_length=None):
        return name
