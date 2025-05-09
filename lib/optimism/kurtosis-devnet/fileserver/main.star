FILESERVER_HTTP_PORT_ID = "http"
FILESERVER_HTTP_PORT_NUM = 80
FILESERVER_IMAGE = "nginx:latest"


def get_used_ports():
    used_ports = {
        FILESERVER_HTTP_PORT_ID: PortSpec(
            number=FILESERVER_HTTP_PORT_NUM,
        )
    }
    return used_ports


def run(plan, source_path, server_image=FILESERVER_IMAGE):
    service_name = "fileserver"
    config = get_fileserver_config(
        plan = plan,
        service_name = service_name,
        source_path = source_path,
        server_image = server_image,
    )
    plan.add_service(
        name = service_name,
        config = config,
    )
    return service_name


def get_fileserver_config(plan, service_name, source_path, server_image):
    files = {}

    # Upload content to container
    content_artifact = plan.upload_files(
        src=source_path,
        name="{}-content".format(service_name),
    )
    files["/content"] = content_artifact

    # Add nginx config file
    nginx_conf = plan.upload_files(
        src="static_files/nginx",
        name="{}-nginx-conf".format(service_name),
    )
    files["/etc/nginx/conf.d"] = nginx_conf

    ports = get_used_ports()
    return ServiceConfig(
        image=server_image,
        ports=ports,
        cmd=["nginx", "-g", "daemon off;"],
        files=files,
    )
