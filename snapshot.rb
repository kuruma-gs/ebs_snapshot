#!/usr/bin/env ruby

#
# Usage: snapshot.rb [config_file] [rotate_tag]
# 
# config_file ... Option. YAML configuration file. See below example. Default is config.yml.
# rotate_tag ... Option. This string is added to the end of the description.
# 
# If the end of the description doesn't match with the rotate_tag value in the config file, 
# the snapshot is not deleted automatically. 
# Please be careful to add the second argument, if you execute snapshot.rb repeatedly.

require 'rubygems'
require 'right_aws'
require 'logger'
require 'yaml'

def config_example
  puts <<'EOF'
# ----------------------------------------------------------------
# config.yml example
# ----------------------------------------------------------------
access_key: ABCDEFGHIJKLMNOPQRST
secret_key: abcdefghijklmnopqrstuvwxyz/ABC1234567890
region: ap-northeast-1
volume_id: vol-abcde123
description: "www.example.com backup"
log_file: /path/to/logfile
rotate: 5
rotate_tag: "[rotate]"
# ----------------------------------------------------------------
EOF
end

conf_file = ARGV[0] || File.dirname(__FILE__) + "/config.yml"
unless File.exist?(conf_file)
  config_example
  exit 1
end

conf = YAML.load(File.read(conf_file))
rotate_tag = ARGV[1]

if conf["log_file"]
  log_file = conf["log_file"]
  if log_file[0] != "/"
    log_file = File.dirname(conf_file) + "/" + log_file
  end
else
  log_file = STDOUT
end
logger = Logger.new(log_file)

required = %w{access_key secret_key region rotate volume_id description rotate_tag}
required.each do |key|
  next unless conf[key].to_s.strip.empty?
  logger.fatal("configuration error: #{key} required.")
  puts "ERROR: #{key} required."
  config_example
  exit 1
end

rotate_tag ||= conf["rotate_tag"]
desc = "#{conf["description"]} #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{rotate_tag}"

ec2  = RightAws::Ec2.new(conf["access_key"], conf["secret_key"], {:region => conf["region"], :logger => logger})
ec2.create_snapshot(conf["volume_id"], desc)
logger.info("snapshot created.")

snapshots = ec2.describe_snapshots
snapshots = snapshots.select{|snapshot| conf["volume_id"] == snapshot[:aws_volume_id]}
snapshots = snapshots.select{|snapshot| snapshot[:aws_description] =~ /#{Regexp.quote(conf["rotate_tag"])}$/}
snapshots = snapshots.sort_by{|snapshot| snapshot[:aws_started_at]}

id   = snapshots.last[:aws_id]
desc = snapshots.last[:aws_description]
logger.info("latest snapshot: #{desc} (#{id})")

delete_num = snapshots.length - conf["rotate"].to_i
delete_num.times do |i| 
  id   = snapshots[i][:aws_id]
  desc = snapshots[i][:aws_description]
  logger.info("delete snapshot: #{desc} (#{id})")
  ec2.delete_snapshot(id)
end
logger.info("done.")
