locals {
  # Get all YAML files in the alert_configs directory
  alert_config_files = fileset(path.module, "alert_configs/*.yaml")
  
  # Load all alert configurations
  alert_configs = {
    for file in local.alert_config_files :
    basename(trimsuffix(file, ".yaml")) => yamldecode(file(file))
  }
  
  # Create a simple map of account configurations
  accounts = {
    for account_key, config in local.alert_configs :
    account_key => {
      name = config.account.name
      id = config.account.id
      region = config.account.region
      auth_type = contains(keys(config.account), "auth_type") ? config.account.auth_type : "default"
      role_arn = contains(keys(config.account), "role_arn") ? config.account.role_arn : null
    }
  }
  
  # Create a simple map of alert rules
  alert_rules = flatten([
    for account_key, config in local.alert_configs : [
      for instance in config.rds_instances : [
        for alert_type, alert in instance.alerts : {
          account_key = account_key
          instance_name = instance.name
          alert_type = alert_type
          enabled = alert.enabled
          threshold = alert_type == "cpu" ? alert.threshold : null
          threshold_gb = alert_type == "storage" ? alert.threshold_gb : null
          for = alert.for
          severity = alert.severity
          description = alert.description
          summary = alert.summary
        }
      ]
    ]
  ])
}

# Create CloudWatch data sources for each account
resource "grafana_data_source" "cloudwatch" {
  for_each = local.accounts

  type = "cloudwatch"
  name = "CloudWatch-${each.value.name}"
  uid  = "cloudwatch-${each.value.id}"

  json_data_encoded = jsonencode({
    authType    = each.value.auth_type == "role" ? "arn" : "keys"
    defaultRegion = each.value.region
    customMetricsNamespaces = "AWS/RDS"
    assumeRoleArn = each.value.auth_type == "role" ? each.value.role_arn : ""
  })

  secure_json_data_encoded = jsonencode({
    accessKey = each.value.auth_type == "role" ? "" : var.aws_access_key
    secretKey = each.value.auth_type == "role" ? "" : var.aws_secret_key
  })
}

# Create a folder for each account
resource "grafana_folder" "rds_monitoring" {
  for_each = local.accounts

  title = "RDS Monitoring - ${each.value.name}"
  uid   = "rds-monitoring-${each.value.id}"
}

# Create alert rules for each instance and alert type
resource "grafana_rule_group" "rds_alerts" {
  for_each = {
    for rule in local.alert_rules :
    "${rule.account_key}-${rule.instance_name}-${rule.alert_type}" => rule
    if rule.enabled
  }

  name             = "RDS Alerts - ${local.accounts[each.value.account_key].name} - ${each.value.instance_name} - ${each.value.alert_type}"
  folder_uid       = grafana_folder.rds_monitoring[each.value.account_key].uid
  interval_seconds = 60

  rule {
    name           = "RDS ${title(each.value.alert_type)} Alert - ${each.value.instance_name}"
    for            = each.value.for
    condition      = "A"
    no_data_state  = "NoData"
    exec_err_state = "Error"
    
    annotations = {
      description = each.value.description
      summary     = each.value.summary
    }
    
    labels = {
      severity = each.value.severity
      account  = local.accounts[each.value.account_key].name
    }
    
    data {
      ref_id = "A"
      relative_time_range {
        from = 600
        to   = 0
      }
      
      datasource_uid = grafana_data_source.cloudwatch[each.value.account_key].uid
      model = jsonencode({
        datasource = {
          type = "cloudwatch"
          uid  = grafana_data_source.cloudwatch[each.value.account_key].uid
        }
        namespace = "AWS/RDS"
        metricName = each.value.alert_type == "cpu" ? "CPUUtilization" : "FreeStorageSpace"
        dimensions = {
          DBInstanceIdentifier = each.value.instance_name
        }
        statistic = "Average"
        period    = "300"
        refId     = "A"
        expression = each.value.alert_type == "cpu" ? "AVG > ${each.value.threshold}" : "AVG < ${each.value.threshold_gb}GB"
      })
    }
  }
} 