from owrx.reporting.reporter import Reporter
from owrx.config import Config
from owrx.property import PropertyDeleted
import json
import threading
import time
from elasticsearch import Elasticsearch
from elasticsearch_dsl import connections

import logging

logger = logging.getLogger(__name__)

es_client_id = "openwebrx"

class ElasticsearchReporter(Reporter):
    client: Elasticsearch | None
    def __init__(self):
        self.client = None
        self.index = None
        self.config_subscription = Config.get().filter(
            "elasticsearch_host", "elasticsearch_index", "elasticsearch_client_kwargs",
            "elasticsearch_username", "elasticsearch_password", "elasticsearch_api_key",
        ).wire(self.setup_client)
        self.setup_client()

    def setup_client(self) -> Elasticsearch:
        config = Config.get()

        if "elasticsearch_host" in config and "elasticsearch_index" in config:
            index = config["elasticsearch_index"]
            try:
                client = connections.get_connection(alias=es_client_id)
            except KeyError:
                client_kwargs = config.get("elasticsearch_client_kwargs", {})
                if "elasticsearch_api_key" in config:
                    client_kwargs["api_key"] = config["elasticsearch_api_key"]
                elif "elasticsearch_username" in config and "elasticsearch_password" in config:
                    client_kwargs["http_auth"] = (config["elasticsearch_username"], config["elasticsearch_password"])
                client = connections.create_connection(
                    alias=es_client_id,
                    hosts=config["elasticsearch_host"],
                    verify_certs=False,
                    **client_kwargs
                )
            self.client = client
            self.index = index

    def stop(self):
        self.client = None
        self.index = None
        self.config_subscription.cancel()

    def spot(self, spot):
        if self.client and self.index:
            try:
                self.client.index(index=self.index, body=json.dumps(spot))
            except Exception:
                logger.exception("Error sending spot to Elasticsearch")