local aws = import 'common/aws/aws.libsonnet';
local core = import 'common/core.libsonnet';
local manifest = import 'common/manifest.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  Role: aws.GlobalResource + {
    local this = self,

    type:: 'aws_iam_role',
    tag:: 'role',
    attributes+:: ['arn'],
    name: null,
    assume_role_service_url:: null,
    path: '/',
    max_session_duration_s: null,
    output_attributes+:: ['arn'],

    assume_role_policy_document:: $.Policy.Document + {
      statements: [$.Policy.Statement + {
        action: 'sts:AssumeRole',
        effect: $.Policy.Effect.ALLOW,
        principal: {
          Service: this.assume_role_service_url,
        },
      }],
    },

    __validate__+:: [{
      name: 'iam.Role',
      validators: [
        core.field('name').required().string(),
        core.field('assume_role_service_url').required().string(),
        core.field('path').required().string(),
        core.field('max_session_duration_s').number(),
        core.field('assume_role_policy_document').child(),
      ],
    }],
    __manifest__+:: {
      rename+: {
        max_session_duration_s: 'max_session_duration',
      },
      overlay+: {
        assume_role_policy: this.assume_role_policy_document.jsonMini(),
      },
    },
  },

  Policy: aws.GlobalResource + {
    local this = self,

    type:: 'aws_iam_policy',
    tag:: 'policy',
    version:: this.Document.version,
    statements:: [],
    path: '/',
    output_attributes+:: ['arn'],

    policy_document:: this.Document + {
      version: this.version,
      statements: this.statements,
    },

    __validate__+:: [{
      name: 'iam.Policy',
      validators: [
        core.field('statements').children(),
        core.field('version').string(),
        core.field('path').string(),
        core.field('policy_document').child(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        policy: this.policy_document.jsonMini(),
      },
    },

    Document:: core.Object + {
      local document = self,
      version: '2012-10-17',
      statements: [],
      __validate__+:: [{
        name: 'iam.Policy.Document',
        validators: [
          core.field('version').string(),
          core.field('statements').children(),
        ],
      }],
      __manifest__+:: {
        rename+: {
          version: 'Version',
          statements: 'Statement',
        },
      },
    },

    Statement:: core.Object + {
      local statement = self,

      action: null,  // Can be either a string or an array of strings
      effect: null,
      principal: null,
      resources: null,  // arn glob string (2025.04.26: array of arn glob string?)

      __validate__+:: [{
        name: 'iam.Policy.Statement',
        validators: [
          core.field('action').required().typeAnyOf(['string', 'array']),
          core.field('effect').required().string(),
        ],
      }],
      __manifest__+:: {
        rename+: {
          action: 'Action',
          effect: 'Effect',
          principal: 'Principal',
          resources: 'Resource',
        },
      },
    },

    Effect:: {
      ALLOW: 'Allow',
    },
  },

  RolePolicyAttachment: aws.GlobalResource + {
    local this = self,

    type:: 'aws_iam_role_policy_attachment',
    tag:: 'role_policy_attachment',
    role:: null,
    role_name:: null,
    policy:: null,
    policy_arn:: null,

    depends_on+: (
      utils.singletonArrayIf(this.role != null, this.role)
      + utils.singletonArrayIf(this.policy != null, this.policy)
    ),

    __validate__+:: [{
      name: 'iam.RolePolicyAttachment',
      validators: [
        core.fields(['role', 'role_name']).exclusive().requireOne(),
        core.fields(['policy', 'policy_arn']).exclusive().requireOne(),
        core.field('role').object(),
        core.field('role_name').string(),
        core.field('policy').object(),
        core.field('policy_arn').string(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        role:::
          if this.role != null
          then this.role.name
          else this.role_name,
        policy_arn:::
          if this.policy != null
          then this.policy.attribute('arn')
          else this.policy_arn,
      },
    },
  },

  // Bundle containing an IAM Role and attachments to given policies
  RoleBundle: aws.GlobalBundle + {
    local this = self,

    role: $.Role + self.common_child_opts,
    policies: [],
    managed_policies: [],
    statements: [],

    inline_policy:
      if std.length(self.statements) > 0
      then $.Policy + self.common_child_opts + {
        tag: 'inline_policy',
        statements: this.statements,
      }
      else null,

    children: [
      this.role,
    ] + (
      utils.singletonArrayIf(std.length(self.statements) > 0, self.inline_policy)
    ) + [
      $.RolePolicyAttachment + {
        tag: '%s_%s_attachment' % [this.role.tag, x.tag],
        role: this.role,
        policy: x,
      }
      for x in this.policies
    ] + [
      $.RolePolicyAttachment + {
        tag: '%s_%s_attachment' % [this.role.tag, policy.name],
        role: this.role,
        policy_arn: policy.arn,
      }
      for policy in this.managed_policies
    ],
  },

  ManagedPolicy: {
    AMAZON_ECS_TASK_EXECUTION_ROLE_POLICY: {
      name: 'amazon_ecs_task_execution_role_policy',
      arn: 'arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy',
    },
    AMAZON_SSM_MANAGED_INSTANCE_CORE: {
      name: 'amazon_ssm_managed_instance_core',
      arn: 'arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore',
    },
    AMAZON_EC2_CONTAINER_REGISTRY_PULL_ONLY: {
      name: 'amazon_ec2_container_registry_pull_only',
      arn: 'arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly',
    },
    AMAZON_API_GATEWAY_PUSH_TO_CLOUD_WATCH_LOGS: {
      name: 'amazon_api_gateway_push_to_cloud_watch_logs',
      arn: 'arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs',
    },
    AMAZON_SSM_MANAGED_EC2_INSTANCE_DEFAULT_POLICY: {
      name: 'amazon_api_gateway_push_to_cloud_watch_logs',
      arn: 'arn:aws:iam::aws:policy/service-role/AmazonSSMManagedEC2InstanceDefaultPolicy',
    },
  },

  ServiceUrl: {
    API_GATEWAY: 'apigateway.amazonaws.com',
    ECS_TASKS: 'ecs-tasks.amazonaws.com',
  },
}