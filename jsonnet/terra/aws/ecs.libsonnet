// Templates for Elastic Container Service resources
local aws = import 'common/aws/aws.libsonnet';
local core = import 'common/core.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  Cluster: aws.RegionResource + {
    local this = self,

    type: 'aws_ecs_cluster',
    tag: 'ecs_cluster',
    cluster_name: null,

    __validate__+:: [{
      name: 'ecs.Cluster',
      validators: [
        core.field('cluster_name').required(),
      ],
    }],

    args+: {
      name: this.cluster_name,
    },
  },

  Service: aws.RegionResource + {
    local this = self,

    type: 'aws_ecs_service',
    tag: 'ecs_service',
    service_name: null,
    cluster: null,
    task_definition: null,
    desired_count: 1,  // Number of tasks
    // Enable ECS Exec:
    // https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html
    enable_execute_command: false,
    scheduling_strategy: this.SchedulingStrategy.REPLICA,
    launch_type: null,
    // Set this when using `awsvpc` network mode
    network_configuration: null,
    service_registry: null,

    __validate__+:: [{
      name: 'ecs.Service',
      validators: [
        core.field('service_name').required(),
        core.field('cluster').required(),
        core.field('task_definition').required(),
      ],
    }],

    args+: {
      name: this.service_name,
      cluster: this.cluster.id(),
      task_definition: this.task_definition.attribute('arn'),
      desired_count: this.desired_count,
      enable_execute_command: this.enable_execute_command,
      scheduling_strategy: this.scheduling_strategy,
      // Some args conflict and should excluded if not specified
      [utils.ifNotNull(this.launch_type, 'launch_type')]: this.launch_type,
      [utils.ifNotNull(this.network_configuration, 'network_configuration')]: this.network_configuration + {
        subnets: [x.id() for x in this.network_configuration.subnets],
        security_groups: [x.id() for x in this.network_configuration.security_groups],
      },
      [utils.ifNotNull(this.service_registry, 'service_registries')]: [this.service_registry.json],
    },

    SchedulingStrategy: {
      REPLICA: 'REPLICA',
      DAEMON: 'DAEMON',
    },

    LaunchType: {
      EC2: 'EC2',
      FARGATE: 'FARGATE',
      EXTERNAL: 'EXTERNAL',
    },

    NetworkConfiguration: {
      // `subnets` and `security_groups` should be provided as jsonnet AWS
      // resources, they will be translated to lists of IDs in the EcsService
      // template.
      subnets: [],
      security_groups: [],
      assign_public_ip: false,
    },

    ServiceRegistry: core.Object + {
      local registry = self,

      cloud_map_service: null,
      // Port that the ECS service listens on. Should be equal to `host_port`
      // specified in the TaskDefinition port mapping.
      port: null,

      __validate__+:: [{
        name: 'ecs.Service.ServiceRegistry',
        validators: [
          core.field('cloud_map_service').required(),
        ],
      }],

      json: {
        registry_arn: registry.cloud_map_service.attribute('arn'),
        [utils.ifNotNull(registry.port, 'port')]: registry.port,
      }
    },
  },

  TaskDefinition: aws.GlobalResource + {
    local this = self,

    type: 'aws_ecs_task_definition',
    tag: 'task_definition',
    attributes+: ['arn'],
    family: null,  // name, essentially
    container_definitions: [],
    requires_compatibilities: [],  // List of LaunchTypes
    // `awsvpc` required when using fargate. Causes each container to receive
    // their own (virtual) IP address. Means that multiple containers in the
    // same ECS service can use the same port, but disallows mapping container
    // ports to different host ports.
    // https://tutorialsdojo.com/ecs-network-modes-comparison/
    network_mode: 'awsvpc',
    cpu: 256,  // 0.25 vCPU, the minimum price tier
    memory: 512,  // 0.5 GiB, the minimum price tier
    runtime_platform: self.RuntimePlatform,
    task_role: null,
    execution_role: null,

    __validate__+:: [{
      name: 'ecs.TaskDefinition',
      validators: [
        core.field('family').required(),
        core.field('container_definitions').nonEmpty().arrayOfObject().children(),
        core.field('task_role').required(),
        core.field('execution_role').required(),
      ],
    }],

    args+: {
      family: this.family,
      container_definitions: std.manifestJsonMinified(this.container_definitions),
      requires_compatibilities: this.requires_compatibilities,
      network_mode: this.network_mode,
      cpu: this.cpu,
      memory: this.memory,
      execution_role_arn: this.execution_role.attribute('arn'),
      task_role_arn: this.task_role.attribute('arn'),
    },

    // https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html
    ContainerDefinition: core.Object + {
      name: null,
      image: null,
      essential: true,
      port_mappings:: [],
      log_configuration:: null,
      environment: [],

      __validate__+:: [{
        name: 'ecs.TaskDefinition.ContainerDefinition',
        validators: [
          core.field('name').required(),
          core.field('image').required(),
          core.field('port_mappings').arrayOfObject().children(),
        ],
      }],

      portMappings: self.port_mappings,
      logConfiguration: self.log_configuration,
    },

    PortMapping: core.Object + {
      protocol: null,
      // Port that the app inside the container listens on
      container:: null,
      // Port that the host instance listens on, forwarding traffic to the
      // container on the container port
      host:: null,

      containerPort: self.container,
      hostPort: self.host,

      __validate__+:: [{
        name: 'ecs.TaskDefinition.PortMapping',
        validators: [
          core.field('protocol').required(),
          core.field('container').required(),
          core.field('host').required(),
        ],
      }],
    },

    RuntimePlatform: core.Object + {
      // https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#runtime-platform
      operating_system_family: this.OperatingSystemFamily.LINUX,
      cpu_archetecture: this.CpuArchetecture.X86_64,

      __validate__+:: [{
        name: 'ecs.TaskDefinition.RuntimePlatform',
        validators: [
          core.field('operating_system_family').required(),
          core.field('cpu_archetecture').required(),
        ],
      }],
    },

    OperatingSystemFamily: {
      LINUX: 'LINUX',
    },

    CpuArchetecture: {
      X86_64: 'X86_64',
      ARM64: 'ARM64',
    },
  },

  Repository: aws.RegionResource + {
    local this = self,

    type: 'aws_ecr_repository',
    tag: 'ecr_repository',
    repository_name: null,  // Repositories can contain namespaces with slashes, e.g. app_name/service_name
    image_tag_mutability: this.ImageTagMutability.MUTABLE,
    scan_on_push: false,

    __validate__+:: [{
      name: 'ecs.Repository',
      validators: [
        core.field('repository_name').required(),
      ],
    }],

    args+: {
      name: this.repository_name,
      image_tag_mutability: this.image_tag_mutability,
      [if this.scan_on_push then 'image_scanning_configuration' else null]: {
        scan_on_push: this.scan_on_push,
      },
    },

    ImageTagMutability: {
      MUTABLE: 'MUTABLE',
      IMMUTABLE: 'IMMUTABLE',
    },
  },

  LifecyclePolicy: aws.RegionResource + {
    local this = self,

    type: 'aws_ecr_lifecycle_policy',
    tag: 'ecr_lifecycle_policy',
    repository: null,
    rules: [],

    __validate__+:: [{
      name: 'ecs.LifecyclePolicy',
      validators: [
        core.field('repository').required(),
        core.field('rules').nonEmpty(),
      ],
    }],

    depends_on+: [
      this.repository,
    ],
    args+: {
      repository: this.repository.repository_name,
      policy: std.manifestJsonMinified({
        rules: [r.json for r in std.sort(this.rules, function(x) x.priority)],
      }),
    },

    Rule: core.Object + {
      local rule = self,
      // https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html#lifecycle_policy_parameters
      priority: null,
      selection: null,
      action: {
        // No other values are allowed as of 2024.10.28
        type: 'expire',
      },

      __validate__+:: [{
        name: 'ecs.LifecyclePolicy.Rule',
        validators: [
          core.field('priority').required(),
          core.field('selection').required().object().child(),
        ]
      }],

      json: {
        rulePriority: rule.priority,
        selection: rule.selection.json,
        action: rule.action,
      },
    },

    Selection: core.Object + {
      local selection = self,

      // https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html#lifecycle_policy_parameters
      tag_status: self.TagStatus.ANY,
      tag_pattern_list: [],
      tag_prefix_list: [],
      image_count_more_than: null,
      days_since_image_pushed: null,

      __validate__+:: [{
        name: 'ecs.LifecyclePolicy.Selection',
        validators: [
          core.fields(['image_count_more_than', 'days_since_image_pushed']).exclusive().requireOne(),
          core.fields(['tag_pattern_list', 'tag_prefix_list']).exclusive(),
        ],
      }],

      json: {
        tagStatus: selection.tag_status,
        [utils.ifNotEmpty(selection.tag_pattern_list, 'tagPatternList')]: selection.tag_pattern_list,
        [utils.ifNotEmpty(selection.tag_prefix_list, 'tagPrefixList')]: selection.tag_prefix_list,
        countType:
          if selection.image_count_more_than != null
          then this.CountType.IMAGE_COUNT_MORE_THAN
          else this.CountType.SINCE_IMAGE_PUSHED,
        countNumber:
          if selection.image_count_more_than != null
          then selection.image_count_more_than
          else selection.days_since_image_pushed,
        [utils.ifNotNull(selection.days_since_image_pushed, 'countUnit')]: 'days',
      },
    },

    TagStatus: {
      TAGGED: 'tagged',
      UNTAGGED: 'untagged',
      ANY: 'ANY',
    },

    CountType: {
      IMAGE_COUNT_MORE_THAN: 'imageCountMoreThan',
      SINCE_IMAGE_PUSHED: 'sinceImagePushed',
    },
  },

  RepositoryBundle: aws.RegionBundle + {
    local this = self,

    service_name: null,
    tag: this.service_name,
    repository: $.Repository + this.common_child_opts + {
      repository_name: this.service_name,
    },
    policy: $.LifecyclePolicy + this.common_child_opts + {
      repository: this.repository,
      rules: [
        // Delete any untagged images older than 14 days
        $.LifecyclePolicy.Rule + {
          priority: 1,
          selection: $.LifecyclePolicy.Selection + {
            tag_status: $.LifecyclePolicy.TagStatus.UNTAGGED,
            days_since_image_pushed: 14,
          },
        },
      ],
    },

    children+: [
      this.repository,
      this.policy,
    ],
  },

  getImage(account_id, repository, tag='latest')::
    '%s.dkr.ecr.%s.amazonaws.com/%s:%s' % [
      account_id,
      repository.region.id,
      repository.repository_name,
      tag,
    ],
}