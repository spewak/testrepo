FROM centos:centos7 AS zeppelin_builder

ARG ZEPPELIN_GIT_REPO="https://github.com/mapr/zeppelin.git"
ARG ZEPPELIN_GIT_TAG="0.9.0-dsr-1.5.0.0"
ARG MAPR_MAVEN_REPO="http://repository.mapr.com/maven/"

RUN yum install -y git wget java-1.8.0-openjdk-devel which bzip2 && \
    mkdir /opt/maven && \
    wget --no-check-certificate https://www.apache.org/dist/maven/maven-3/3.5.4/binaries/apache-maven-3.5.4-bin.tar.gz -O maven.tar.gz && \
    tar xf maven.tar.gz --strip-components=1 -C /opt/maven && \
    ln -s /opt/maven/bin/mvn /usr/local/bin/mvn

RUN \
    git clone -q "$ZEPPELIN_GIT_REPO" --single-branch -b "$ZEPPELIN_GIT_TAG" zeppelin && \
    cd zeppelin && \
    mvn -B clean package -DskipTests -P 'scala-2.11,spark-mapr,build-distr,vendor-repo-mapr' && \
    ZEPPELIN_MAVEN_VERSION=$(mvn -B help:evaluate -Dexpression=project.version -q -DforceStdout) && \
    mv "./zeppelin-distribution/target/zeppelin-${ZEPPELIN_MAVEN_VERSION}/zeppelin-${ZEPPELIN_MAVEN_VERSION}" /zeppelin_build


FROM centos:centos7

ARG ZEPPELIN_VERSION="0.9.0"
ARG MAPR_VERSION_CORE="6.1.1"
ARG MAPR_VERSION_MEP="6.3.4"
ARG MAPR_REPO_ROOT="https://package.mapr.com/releases"

ARG DRILL_DRIVER_URL="http://package.mapr.com/tools/MapR-JDBC/MapR_Drill/MapRDrill_jdbc_v1.6.8.1011/MapRDrillJDBC-1.6.8.1011.zip"

LABEL mapr.os=centos7 mapr.version=$MAPR_VERSION_CORE mapr.mep_version=$MAPR_VERSION_MEP

ENV container docker

RUN yum install -y curl initscripts net-tools sudo wget which syslinux openssl file java-1.8.0-openjdk-devel unzip

RUN mkdir -p /opt/mapr/installer/docker/ && \
    wget "${MAPR_REPO_ROOT}/installer/redhat/mapr-setup.sh" -P /opt/mapr/installer/docker/ && \
    chmod +x /opt/mapr/installer/docker/mapr-setup.sh

RUN /opt/mapr/installer/docker/mapr-setup.sh -r "$MAPR_REPO_ROOT" container client "$MAPR_VERSION_CORE" "$MAPR_VERSION_MEP" mapr-client mapr-posix-client-container mapr-hbase mapr-pig mapr-spark mapr-kafka mapr-livy

RUN yum install -y git jq less nano patch vim && \
    yum install -y gcc gcc-c++ python3-devel python3-pip && \
    python3 -m pip install --upgrade pip && \
    python3 -m pip install matplotlib numpy pandas

RUN mkdir -p /opt/mapr/zeppelin && \
    echo "$ZEPPELIN_VERSION" > /opt/mapr/zeppelin/zeppelinversion

COPY --from=zeppelin_builder /zeppelin_build "/opt/mapr/zeppelin/zeppelin-$ZEPPELIN_VERSION"

RUN ZEPPELIN_HOME="/opt/mapr/zeppelin/zeppelin-${ZEPPELIN_VERSION}" ;\
    ln -s "${ZEPPELIN_HOME}/bin/entrypoint.sh" "/entrypoint.sh" ;\
    cat "${ZEPPELIN_HOME}/dsr/misc/profile.d/mapr.sh" >> /etc/profile.d/mapr.sh

RUN mkdir -p /opt/mapr/zeppelin/thirdparty/jdbc-mapr-drill && \
    curl -sS -o /tmp/drill_jdbc.zip "$DRILL_DRIVER_URL" && \
    unzip -q -d /tmp/drill_jdbc /tmp/drill_jdbc.zip && \
    unzip -q -d /opt/mapr/zeppelin/thirdparty/jdbc-mapr-drill /tmp/drill_jdbc/*.zip && \
    rm -rf /tmp/drill_jdbc /tmp/drill_jdbc.zip

RUN rm /etc/yum.repos.d/mapr_*.repo && \
    yum -q clean all && \
    rm -rf /var/lib/yum/history/* && \
    find /var/lib/yum/yumdb/ -name origin_url -exec rm {} \;

EXPOSE 9995
EXPOSE 10000-10010
EXPOSE 11000-11010

ENTRYPOINT [ "/entrypoint.sh" ]
