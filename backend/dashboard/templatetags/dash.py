from django import template
from django.db.models.fields.files import FieldFile
from django.utils.html import format_html
from django.utils.timezone import localtime

register = template.Library()

BADGE = {
    "confirmed": "bg-green-100 text-green-800", "paid": "bg-green-100 text-green-800",
    "completed": "bg-slate-100 text-slate-700", "done": "bg-slate-100 text-slate-700",
    "held": "bg-amber-100 text-amber-800", "pending": "bg-amber-100 text-amber-800", "open": "bg-blue-100 text-blue-800",
    "cancelled": "bg-orange-100 text-orange-800", "refunded": "bg-orange-100 text-orange-800",
    "expired": "bg-slate-100 text-slate-500", "failed": "bg-red-100 text-red-700",
    "live": "bg-red-100 text-red-700", "next": "bg-blue-100 text-blue-800", "tbd": "bg-amber-100 text-amber-800",
    "draft": "bg-slate-100 text-slate-600", "upcoming": "bg-blue-100 text-blue-800",
    "replied": "bg-green-100 text-green-800", "closed": "bg-slate-100 text-slate-600",
}


def resolve(obj, path):
    val = obj
    for part in path.split("__"):
        if val is None:
            return None
        val = getattr(val, part, None)
        if callable(val) and not isinstance(val, FieldFile):
            val = val()
    return val


@register.simple_tag
def cell(obj, column):
    path, kind = column["path"], column["kind"]
    val = resolve(obj, path)
    if kind == "image":
        url = ""
        try:
            url = val.url if val else ""
        except ValueError:
            url = ""
        if not url:
            return format_html('<div class="h-10 w-10 rounded-lg bg-slate-100"></div>')
        return format_html('<img src="{}" class="h-10 w-10 rounded-lg object-cover" alt="">', url)
    if kind == "bool":
        if val:
            return format_html('<span class="inline-flex h-6 items-center rounded-full bg-green-100 px-2 text-xs font-semibold text-green-800">Yes</span>')
        return format_html('<span class="inline-flex h-6 items-center rounded-full bg-slate-100 px-2 text-xs font-semibold text-slate-500">No</span>')
    if kind == "money":
        return format_html("₹{}", f"{val or 0:,}")
    if kind == "color":
        return format_html('<span class="inline-flex items-center gap-2"><span class="h-4 w-4 rounded" style="background:{}"></span>{}</span>', val, val)
    if kind == "date":
        if not val:
            return "—"
        try:
            return localtime(val).strftime("%d %b %Y")
        except (ValueError, AttributeError):
            return val.strftime("%d %b %Y")
    if kind == "badge":
        label = val
        display = getattr(obj, f"get_{path}_display", None)
        if display:
            label = display()
        return format_html('<span class="inline-flex h-6 items-center rounded-full px-2 text-xs font-semibold {}">{}</span>',
                           BADGE.get(str(val), "bg-slate-100 text-slate-700"), label)
    if val is None or val == "":
        return "—"
    return str(val)


@register.filter
def badge_class(value):
    return BADGE.get(str(value), "bg-slate-100 text-slate-700")


@register.filter
def inr(value):
    try:
        return f"₹{int(value):,}"
    except (TypeError, ValueError):
        return "₹0"


@register.filter
def hour(h):
    try:
        h = int(h)
    except (TypeError, ValueError):
        return h
    return f"{(h % 12) or 12} {'AM' if h % 24 < 12 else 'PM'}"
