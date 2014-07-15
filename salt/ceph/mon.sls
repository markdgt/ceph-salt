# vi: set ft=yaml.jinja :

{% set cluster = salt['grains.get']('environment','ceph') %}
{% set host = salt['config.get']('host') %}
{% set ip = salt['config.get']('fqdn_ip4') %}
{% set fsid = salt['pillar.get']('ceph:global:fsid') %}
{% set keyring = '/etc/ceph/' + cluster + '.client.admin.keyring' %}
{% set secret = '/tmp/' + cluster + '.mon.keyring' %}
{% set monmap = '/tmp/' + cluster + 'monmap' %}
{% set nodes = salt['pillar.get']('nodes').iterkeys() %}
{% set mons = [] %}

{% for node in nodes %}

{% set is_mon = salt['pillar.get']('nodes:' + node + ':mon') %}

{% if is_mon == true %}
{% do mons.append(node) -%}
{% endif %}

{% endfor %}

include:
  - .ceph

/var/lib/ceph/mon/{{ cluster }}-{{ host }}:
  file.directory:
    - user: root
    - group: root
    - mode: '0644'
    - require:
      - pkg: ceph

{{ keyring }}:
  cmd.run:
    - name: echo "Keyring doesn't exists"
    - unless: test -f {{ keyring }}

{% for mon in mons %}
cp.get_file {{mon}}{{ keyring }}:
  module.wait:
    - name: cp.get_file
    - path: salt://{{ mon }}/files{{ keyring }}
    - dest: {{ keyring }}
    - watch:
      - cmd: {{ keyring }}
{% endfor %}

get_mon_secret:
  cmd.run:
    - name: ceph auth get mon. -o {{ secret }}
    - onlyif: test -f {{ keyring }}

get_mon_map:
  cmd.run:
    - name: ceph mon getmap -o {{ monmap }}
    - onlyif: test -f {{ keyring }}

gen_mon_secret:
  cmd.run:
    - name: ceph-authtool --create-keyring {{ secret }} --gen-key -n mon. --cap mon 'allow *'
    - unless: test -f /var/lib/ceph/mon/{{ cluster }}-{{ host }}/keyring || test -f {{ secret }}

gen_admin_keyring:
  cmd.run:
    - name: ceph-authtool --create-keyring {{ keyring }} --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'
    - unless: test -f /var/lib/ceph/mon/{{ cluster }}-{{ host }}/keyring || test -f {{ keyring }}

import_keyring:
  cmd.wait:
    - name: ceph-authtool {{ secret }} --import-keyring {{ keyring }}
    - unless: ceph-authtool {{ secret }} --list | grep '^\[client.admin\]'
    - watch:
      - cmd: gen_mon_secret
      - cmd: gen_admin_keyring

cp.push {{ keyring }}:
  module.wait:
    - name: cp.push
    - path: {{ keyring }}
    - watch:
      - cmd: import_keyring

gen_mon_map:
  cmd.wait:
    - name: monmaptool --create --add {{ host }} {{ ip }} --fsid {{ fsid }} {{ monmap }}
    - watch:
      - module: cp.push {{ keyring }}

populate_mon:
  cmd.wait:
    - name: ceph-mon --mkfs -i {{ host }} --monmap {{ monmap }} --keyring {{ secret }}
