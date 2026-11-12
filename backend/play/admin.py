from django.contrib import admin

from .models import RSVP, FriendRequest, Fixture, Game, Group, GroupMember, Tournament, TournamentTeam

admin.site.register([Group, GroupMember, FriendRequest, Game, RSVP, Tournament, TournamentTeam, Fixture])
