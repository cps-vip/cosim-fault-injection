import helics as h
import logging

logger = logging.getLogger("Relay")
logger.addHandler(logging.StreamHandler())
logger.setLevel(logging.DEBUG)

if __name__ == "__main__":
    fed = h.helicsCreateValueFederateFromConfig("Relay_config.json")
    federate_name = h.helicsFederateGetName(fed)
    logger.info("HELICS Version: {}".format(h.helicsGetVersion()))
    logger.info(
        "{}: Federate {} has been registered".format(federate_name, federate_name)
    )

    # Publications and subscriptions
    pubkeys_count = h.helicsFederateGetPublicationCount(fed)
    subkeys_count = h.helicsFederateGetInputCount(fed)

    pubid = {
        i: h.helicsFederateGetPublicationByIndex(fed, i) for i in range(pubkeys_count)
    }
    subid = {i: h.helicsFederateGetInputByIndex(fed, i) for i in range(subkeys_count)}

    # Set defaults for subscriptions
    for i in range(subkeys_count):
        h.helicsInputSetDefaultComplex(subid[i], 0, 0)

    h.helicsFederateEnterInitializingMode(fed)
    h.helicsFederateEnterExecutingMode(fed)

    grantedtime = -1
    sensing_interval = 5 * 60  # 5 minutes
    total_interval = 60 * 60 * 24  # 24 hours
    threshold = 1.0  # Current threshold to trip relay

    for t in range(0, total_interval, sensing_interval):
        while grantedtime < t:
            grantedtime = h.helicsFederateRequestTime(fed, t)

        # Check current drop
        current = h.helicsInputGetComplex(subid[0])  # CurrentA
        logger.info("{}: Current reading = {}".format(federate_name, current))

        if abs(current) < threshold:
            logger.info("{}: Relay tripped at t={}".format(federate_name, grantedtime))
            h.helicsPublicationPublishString(pubid[0], "TRIPPED")

    # Terminate federate
    t = 60 * 60 * 24
    while grantedtime < t:
        grantedtime = h.helicsFederateRequestTime(fed, t)

    logger.info("{}: Destroying federate".format(federate_name))
    h.helicsFederateDisconnect(fed)
    h.helicsFederateFree(fed)
    h.helicsCloseLibrary()
    logger.info("{}: Done!".format(federate_name))
