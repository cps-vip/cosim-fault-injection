import helics as h
import logging

logger = logging.getLogger("CC")
logger.addHandler(logging.StreamHandler())
logger.setLevel(logging.DEBUG)

if __name__ == "__main__":
    fed = h.helicsCreateValueFederateFromConfig("CC_config.json")
    federate_name = h.helicsFederateGetName(fed)
    logger.info("HELICS Version: {}".format(h.helicsGetVersion()))
    logger.info(
        "{}: Federate {} has been registered".format(federate_name, federate_name)
    )

    # Publications and subscriptions
    pubid = {
        i: h.helicsFederateGetPublicationByIndex(fed, i)
        for i in range(h.helicsFederateGetPublicationCount(fed))
    }
    subid = {
        i: h.helicsFederateGetInputByIndex(fed, i)
        for i in range(h.helicsFederateGetInputCount(fed))
    }

    # Set defaults
    for i in range(h.helicsFederateGetInputCount(fed)):
        h.helicsInputSetDefaultString(subid[i], "")

    h.helicsFederateEnterInitializingMode(fed)
    h.helicsFederateEnterExecutingMode(fed)

    grantedtime = -1
    sensing_interval = 5 * 60
    total_interval = 60 * 60 * 24

    for t in range(0, total_interval, sensing_interval):
        while grantedtime < t:
            grantedtime = h.helicsFederateRequestTime(fed, t)

        # Check if relay tripped
        if h.helicsInputIsUpdated(subid[0]):
            status = h.helicsInputGetString(subid[0])
            logger.info("{}: Relay status = {}".format(federate_name, status))

            if status == "TRIPPED":
                # Publish dummy coordinates
                coords = "5.0,-3.0"
                logger.info(
                    "{}: Publishing dummy fault coordinates: {}".format(
                        federate_name, coords
                    )
                )
                h.helicsPublicationPublishString(pubid[0], coords)

    # Terminate federate
    t = 60 * 60 * 24
    while grantedtime < t:
        grantedtime = h.helicsFederateRequestTime(fed, t)

    logger.info("{}: Destroying federate".format(federate_name))
    h.helicsFederateDisconnect(fed)
    h.helicsFederateFree(fed)
    h.helicsCloseLibrary()
    logger.info("{}: Done!".format(federate_name))
