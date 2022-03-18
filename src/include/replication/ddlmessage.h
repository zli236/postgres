/*-------------------------------------------------------------------------
 * ddlmessage.h
 *	   Exports from replication/logical/ddlmessage.c
 *
 * Copyright (c) 2022, PostgreSQL Global Development Group
 *
 * src/include/replication/ddlmessage.h
 *-------------------------------------------------------------------------
 */
#ifndef PG_LOGICAL_DDL_MESSAGE_H
#define PG_LOGICAL_DDL_MESSAGE_H

#include "access/xlog.h"
#include "access/xlogdefs.h"
#include "access/xlogreader.h"

/*
 * Generic logical decoding DDL message wal record.
 */
typedef struct xl_logical_ddl_message
{
	Oid			dbId;			/* database Oid emitted from */
	bool		transactional;	/* is message transactional? */
	Size		prefix_size;	/* length of prefix */
	Size		role_size;      /* length of the role that executes the DDL command */
	Size		search_path_size; /* length of the search path */
	Size		message_size;	  /* size of the message */
	/*
	 * payload, including null-terminated prefix of length prefix_size
	 * and null-terminated role of length role_size
	 * and null-terminated search_path of length search_path_size
	 */
	char		message[FLEXIBLE_ARRAY_MEMBER];
} xl_logical_ddl_message;

#define SizeOfLogicalDDLMessage	(offsetof(xl_logical_ddl_message, message))

extern XLogRecPtr LogLogicalDDLMessage(const char *prefix, Oid roleoid, const char *ddl_message,
									   size_t size, bool transactional);

/* RMGR API*/
#define XLOG_LOGICAL_DDL_MESSAGE	0x00
void		logicalddlmsg_redo(XLogReaderState *record);
void		logicalddlmsg_desc(StringInfo buf, XLogReaderState *record);
const char *logicalddlmsg_identify(uint8 info);

#endif							/* PG_LOGICAL_DDL_MESSAGE_H */
