from elasticsearch import Elasticsearch
from owrx.reporting.reporter import Reporter
from owrx.config import Config
import json
import logging

logger = logging.getLogger(__name__)

class ElasticsearchReporter(Reporter):
    def __init__(self):
        self.client = None
        self.index = None
        self.configSub = Config.get().filter(
            "elasticsearch_host", "elasticsearch_index", "elasticsearch_client_kwargs",
            "elasticsearch_username", "elasticsearch_password"
        ).wire(self.setupClient)
        self.setupClient()

    def setupClient(self, *args):
        config = Config.get()
        if "elasticsearch_host" in config and "elasticsearch_index" in config:
            client_kwargs = config.get("elasticsearch_client_kwargs", {})
            if "elasticsearch_username" in config and "elasticsearch_password" in config:
                client_kwargs["http_auth"] = (config["elasticsearch_username"], config["elasticsearch_password"])
            self.client = Elasticsearch([config["elasticsearch_host"]], **client_kwargs)
            self.index = config["elasticsearch_index"]
        else:
            self.client = None
            self.index = None

    def stop(self):
        self.client = None
        self.index = None
        self.configSub.cancel()

    def spot(self, spot):
        if self.client and self.index:
            try:
                self.client.index(index=self.index, body=json.dumps(spot))
            except Exception:
                logger.exception("Error sending spot to Elasticsearch")
