#!/usr/bin/env python
# encoding: utf-8
"""
kommissionierbelege.py

Created by Christian Klein on 2011-01-03.
Copyright (c) 2011 HUDORA. All rights reserved.
"""

from husoftm2.lieferscheine import get_ls_kb_data
from husoftm2.tools import remove_prefix, sql_quote
from husoftm2.backend import query


def get_kommibeleg(komminr, header_only=False):
    """Gibt einen Kommissionierbeleg zurück"""

    prefix = 'KA'
    if komminr.startswith('KB'):
        prefix = 'KB'
    komminr = remove_prefix(komminr, prefix)

    # In der Tabelle ALK00 stehen Kommissionierbelege und Lieferscheine.
    # Die Kommissionierbelege haben '0' als Lieferscheinnr.
    # Zusätzlich werden die (logisch) gelöschten Lieferscheine rausgefiltert.
    conditions = ["LKLFSN = 0", "LKKBNR = %s" % sql_quote(komminr), "LKSTAT<>'X'"]
    try:
        belege = get_ls_kb_data(conditions, header_only=header_only,
                                is_lieferschein=False)
    except RuntimeError:
        return {}

    if belege:
        beleg = belege[0]
        # Falls es bereits einen Lieferschein gibt, die Lieferscheinnr in das dict schreiben.
        # Ansonsten die Eintrag 'lieferscheinnr' entfernen (wäre sonst SL0)
        rows = query(['ALK00'], condition="LKLFSN <> 0 AND LKKBNR = %s" % sql_quote(komminr))
        if rows:
            beleg['lieferscheinnr'] = rows[0]['lieferscheinnr']
        else:
            beleg.pop('lieferscheinnr', None)
        return beleg
    return {}
