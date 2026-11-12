"""NCR launch: Gurgaon is live; Delhi, Noida, Greater Noida, Ghaziabad and Faridabad show as "Coming soon".

Cities that already existed before `is_live` was added stay pickable, so nothing changes for them.
Re-running is safe (get_or_create). Toggle "Live" per city in the admin panel.
"""
from django.db import migrations

NCR = [
    # (city, live, [(area, lat, lng), ...])
    ("Gurgaon", True, [
        ("DLF Phase 1", 28.4723, 77.0960), ("Cyber City", 28.4950, 77.0890), ("MG Road", 28.4796, 77.0806),
        ("Golf Course Road", 28.4497, 77.0953), ("Sushant Lok", 28.4626, 77.0784), ("Sector 29", 28.4691, 77.0627),
        ("South City", 28.4525, 77.0610), ("Sohna Road", 28.4167, 77.0430), ("Palam Vihar", 28.5084, 77.0395),
        ("Sector 56", 28.4239, 77.1046),
    ]),
    ("Delhi", False, [
        ("Connaught Place", 28.6315, 77.2167), ("Saket", 28.5245, 77.2066), ("Vasant Kunj", 28.5293, 77.1530),
        ("Dwarka", 28.5921, 77.0460), ("Janakpuri", 28.6219, 77.0878), ("Rohini", 28.7495, 77.0565),
        ("Lajpat Nagar", 28.5677, 77.2433), ("Mayur Vihar", 28.6091, 77.2948),
    ]),
    ("Noida", False, [
        ("Sector 18", 28.5708, 77.3260), ("Sector 50", 28.5713, 77.3624), ("Sector 62", 28.6270, 77.3725),
        ("Sector 76", 28.5670, 77.3843), ("Sector 137", 28.5098, 77.4057),
    ]),
    ("Greater Noida", False, [
        ("Pari Chowk", 28.4646, 77.5100), ("Alpha 1", 28.4744, 77.5040), ("Knowledge Park", 28.4705, 77.4900),
        ("Greater Noida West", 28.6081, 77.4380),
    ]),
    ("Ghaziabad", False, [
        ("Indirapuram", 28.6460, 77.3695), ("Vaishali", 28.6448, 77.3393), ("Kaushambi", 28.6409, 77.3236),
        ("Raj Nagar Extension", 28.6889, 77.4380),
    ]),
    ("Faridabad", False, [
        ("Sector 15", 28.3949, 77.3216), ("Sector 21", 28.4194, 77.2966), ("NIT", 28.3810, 77.3020),
        ("Greater Faridabad", 28.4200, 77.3700),
    ]),
]


def add_ncr(apps, schema_editor):
    City = apps.get_model("venues", "City")
    Area = apps.get_model("venues", "Area")
    City.objects.update(is_live=True)  # keep existing cities pickable
    for order, (name, live, areas) in enumerate(NCR):
        city, created = City.objects.get_or_create(name=name, defaults={"order": order, "is_live": live, "is_popular": True})
        if not created:
            city.is_live = live
            city.save(update_fields=["is_live"])
        for ai, (area, lat, lng) in enumerate(areas):
            Area.objects.get_or_create(city=city, name=area, defaults={"lat": lat, "lng": lng, "order": ai})


class Migration(migrations.Migration):
    dependencies = [("venues", "0002_city_is_live")]
    operations = [migrations.RunPython(add_ncr, migrations.RunPython.noop)]
